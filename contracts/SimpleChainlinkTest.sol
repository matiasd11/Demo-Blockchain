// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

contract SimpleChainlinkTest is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    // --- CONFIGURACIÓN SEPOLIA (Hardcodeada para facilitar) ---
    address router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 donId = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    
    uint64 public subscriptionId;
    uint32 public gasLimit = 300000;

    // --- ESTADO ---
    uint256 public lastScore;     // Aquí aparecerá el 100
    string public status;         // Para que leas qué está pasando
    bytes public lastError;       // Si algo falla, queda aquí

    event ResponseReceived(bytes32 indexed requestId, uint256 result, bytes err);

    constructor(uint64 _subId) FunctionsClient(router) {
        subscriptionId = _subId;
        status = "Deployado. Listo para testear.";
    }

    // Llama a esta función para probar
    function testConnection() external returns (bytes32) {
        FunctionsRequest.Request memory req;

        // SCRIPT JS: Muy simple, no llama a APIs, solo devuelve 100.
        // Esto aísla el problema: probamos la tubería, no la API externa.
        string memory source = "return Functions.encodeUint256(100);";
        
        req.initializeRequestForInlineJavaScript(source);

        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donId
        );

        status = "Solicitud enviada... Esperando a Chainlink";
        return requestId;
    }

    // Chainlink llama a esto automáticamente
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        if (err.length > 0) {
            lastError = err;
            status = "Error recibido de Chainlink";
        } else {
            // Decodificamos el 100
            lastScore = abi.decode(response, (uint256));
            status = "EXITO! Conexion confirmada.";
        }
        emit ResponseReceived(requestId, lastScore, err);
    }
}