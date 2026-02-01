// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract PingPongOracleMock is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    // --- CONFIGURACIÓN SEPOLIA (Correcta) ---
    address router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 donId = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    
    uint64 public subscriptionId;
    uint32 public gasLimit = 300000;

    // --- FUENTES (TU MOCK API) ---
    // Repetimos la URL para simular 3 fuentes distintas y probar el promedio
    string[] public apiUrls = [
        "https://api-mock-render.onrender.com/score",
        "https://api-mock-render.onrender.com/score",
        "https://api-mock-render.onrender.com/score"
    ];

    // 1. Script para buscar el dato (Fetch)
    string constant sourceFetch = 
        "const url = args[0];"
        "const apiResponse = await Functions.makeHttpRequest({ url: url, method: 'GET' });"
        "if (apiResponse.error) { throw Error('Fallo API'); }"
        "return Functions.encodeUint256(apiResponse.data.score);";

    // 2. Script para calcular el promedio (Average)
    string constant sourceAverage = 
        "const scores = args.map(s => parseInt(s));"
        "const sum = scores.reduce((a, b) => a + b, 0);"
        "const avg = Math.round(sum / scores.length);"
        "return Functions.encodeUint256(avg);";

    // --- ESTADO ---
    enum RequestType { FETCH, CALCULATE }

    struct RequestContext {
        uint256 projectId;
        RequestType rType;
    }

    struct Round {
        uint256[] rawScores;    // Debería llenarse con [87, 87, 87]
        uint256 finalAverage;   // Debería ser 87
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
    // PASO 1: DISPARAR LAS CONSULTAS (CORREGIDO)
    // ---------------------------------------------------------
    function startAudit(uint256 _projectId, string[] memory _coords) external {
        currentRound[_projectId]++;
        uint256 roundId = currentRound[_projectId];
        
        // Reiniciamos datos de la ronda
        delete rounds[_projectId][roundId];

        for (uint i = 0; i < apiUrls.length; i++) {
            FunctionsRequest.Request memory req;
            req.initializeRequestForInlineJavaScript(sourceFetch);
            
            // CORRECCIÓN: Ahora el array es de tamaño 3 para incluir coords
            string[] memory args = new string[](3);
            args[0] = apiUrls[i]; // URL
            args[1] = _coords[0]; // Latitud (Ahora sí usamos la variable)
            args[2] = _coords[1]; // Longitud (Ahora sí usamos la variable)
            
            req.setArgs(args);

            bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
            
            pendingRequests[requestId] = RequestContext(_projectId, RequestType.FETCH);
        }
    }

    // ---------------------------------------------------------
    // CALLBACK CENTRAL
    // ---------------------------------------------------------
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        if (err.length > 0) return; 

        RequestContext memory ctx = pendingRequests[requestId];
        uint256 projectId = ctx.projectId;
        uint256 roundId = currentRound[projectId];
        Round storage round = rounds[projectId][roundId];

        // --- A: Recibimos un 87 de la API ---
        if (ctx.rType == RequestType.FETCH) {
            uint256 score = abi.decode(response, (uint256));
            
            round.rawScores.push(score);
            emit DataCollected(projectId, score, "MockAPI");

            // Si tenemos 3 respuestas, pedimos el cálculo
            if (round.rawScores.length == apiUrls.length) {
                _requestCalculationFromChainlink(projectId, round.rawScores);
            }
        } 
        
        // --- B: Recibimos el Promedio Final ---
        else if (ctx.rType == RequestType.CALCULATE) {
            uint256 average = abi.decode(response, (uint256));
            
            round.finalAverage = average;
            round.isComplete = true;
            
            emit RoundFinalized(projectId, average);
        }
    }

    // ---------------------------------------------------------
    // PASO 2: CÁLCULO
    // ---------------------------------------------------------
    function _requestCalculationFromChainlink(uint256 _projectId, uint256[] memory _scores) internal {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(sourceAverage);

        string[] memory args = new string[](_scores.length);
        for(uint i = 0; i < _scores.length; i++) {
            args[i] = _scores[i].toString();
        }
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
        
        pendingRequests[requestId] = RequestContext(_projectId, RequestType.CALCULATE);
        
        emit CalculationRequested(_projectId, requestId);
    }
}