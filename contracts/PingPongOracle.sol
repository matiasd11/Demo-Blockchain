// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract PingPongOracle is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    // --- CONFIGURACIÓN (Sepolia) ---
    address router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 donId = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    uint64 subscriptionId;
    uint32 gasLimit = 300000;

    // --- FUENTES ---
    // Las distintas IAs que consultaremos
    string[] public apiUrls = [
        "https://api.ia-1.com/score",
        "https://api.ia-2.com/score",
        "https://api.ia-3.com/score"
    ];

    // --- CÓDIGOS JS ---
    string public sourceFetch;     // JS para ir a buscar el dato
    string public sourceAverage;   // JS para calcular el promedio

    // --- ESTADO ---
    enum RequestType { FETCH, CALCULATE }

    struct RequestContext {
        uint256 projectId;
        RequestType rType;
    }

    struct Round {
        uint256[] rawScores;    // Datos crudos recolectados [80, 90, 100]
        uint256 finalAverage;   // El resultado que devuelve Chainlink después
        bool isComplete;
    }

    mapping(uint256 => mapping(uint256 => Round)) public rounds;
    mapping(uint256 => uint256) public currentRound;
    mapping(bytes32 => RequestContext) private pendingRequests;

    event DataCollected(uint256 projectId, uint256 score, string source);
    event CalculationRequested(uint256 projectId, bytes32 requestId);
    event RoundFinalized(uint256 projectId, uint256 finalAverage);

    constructor(uint64 _subId) FunctionsClient(router) {
        subscriptionId = _subId;
    }

    // ---------------------------------------------------------
    // PASO 1: DISPARAR LAS CONSULTAS INDIVIDUALES
    // ---------------------------------------------------------
    function startAudit(uint256 _projectId, string[] memory _coords) external {
        currentRound[_projectId]++;
        uint256 roundId = currentRound[_projectId];
        
        // Lanzamos una solicitud por cada API
        for (uint i = 0; i < apiUrls.length; i++) {
            FunctionsRequest.Request memory req;
            req.initializeRequestForInlineJavaScript(sourceFetch);
            
            // Pasamos URL y Coordenadas a este nodo específico
            string[] memory args = new string[](3);
            args[0] = apiUrls[i];
            args[1] = _coords[0];
            args[2] = _coords[1];
            req.setArgs(args);

            bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
            
            // Marcamos que esta solicitud es de TIPO FETCH
            pendingRequests[requestId] = RequestContext(_projectId, RequestType.FETCH);
        }
    }

    // ---------------------------------------------------------
    // CALLBACK CENTRAL (MANEJA TODO)
    // ---------------------------------------------------------
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        if (err.length > 0) return; // Manejo de errores

        RequestContext memory ctx = pendingRequests[requestId];
        uint256 projectId = ctx.projectId;
        uint256 roundId = currentRound[projectId];
        Round storage round = rounds[projectId][roundId];

        // --- ESCENARIO A: LLEGA UN DATO DE UNA IA ---
        if (ctx.rType == RequestType.FETCH) {
            uint256 score = abi.decode(response, (uint256));
            
            // Guardamos el dato crudo (Transparencia)
            round.rawScores.push(score);
            emit DataCollected(projectId, score, "IA_Source");

            // LOGICA AUTOMÁTICA: ¿Ya llegaron todos los datos?
            // Si tenemos 3 respuestas de las 3 APIs, activamos el cálculo
            if (round.rawScores.length == apiUrls.length) {
                _requestCalculationFromChainlink(projectId, round.rawScores);
            }
        } 
        
        // --- ESCENARIO B: LLEGA EL PROMEDIO CALCULADO ---
        else if (ctx.rType == RequestType.CALCULATE) {
            uint256 average = abi.decode(response, (uint256));
            
            // Guardamos solo el resultado final
            round.finalAverage = average;
            round.isComplete = true;
            
            emit RoundFinalized(projectId, average);
            // Aquí podrías llamar a la función de cambio de fase
        }
    }

    // ---------------------------------------------------------
    // PASO 2: ENVIAR DATOS A CHAINLINK PARA CALCULAR
    // ---------------------------------------------------------
    function _requestCalculationFromChainlink(uint256 _projectId, uint256[] memory _scores) internal {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(sourceAverage);

        // Convertimos el array de uint a string[] para pasarlo como args
        string[] memory args = new string[](_scores.length);
        for(uint i = 0; i < _scores.length; i++) {
            args[i] = _scores[i].toString();
        }
        req.setArgs(args);

        // Enviamos la solicitud de CÁLCULO
        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
        
        // Marcamos que esta solicitud es de TIPO CALCULATE
        pendingRequests[requestId] = RequestContext(_projectId, RequestType.CALCULATE);
        
        emit CalculationRequested(_projectId, requestId);
    }

    // Configuración de scripts
    function setScripts(string memory _fetch, string memory _avg) external {
        sourceFetch = _fetch;
        sourceAverage = _avg;
    }
}