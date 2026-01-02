// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

interface INodeScoring {
    function requestScore(bytes32 _requestId, uint256 _coordX, uint256 _coordY) external;
}

interface IMainNode {
     function submitScore(bytes32 _requestId, uint256 score) external;
}

contract DemoScoringNodes is IMainNode{

    struct ScoringRequest {
        uint256 coordX;
        uint256 coordY;
        address[] nodes;
        mapping(address => uint256) scores;
        mapping(address => bool) hasResponded;
        uint256 respondedCount;
        uint256 totalNodes;
        uint256 averageScore;
        bool isComplete;
    }

    mapping(bytes32 => ScoringRequest) public requests;
    uint256 private requestCounter;

    event ScoringRequested(bytes32 indexed requestId, uint256 coordX, uint256 coordY, uint256 nodeCount);
    event ScoreReceived(bytes32 indexed requestId, address indexed node, uint256 score);
    event AverageCalculated(bytes32 indexed requestId, uint256 average);

    // 1. Solicitar scoring a múltiples nodos (asincrónico)
    function requestNodeScoring(uint256 _coordX, uint256 _coordY, address[] calldata _nodes)
        external
        returns (bytes32)
    {
        require(_nodes.length > 0, "No nodes provided");

        bytes32 requestId = keccak256(abi.encodePacked(block.timestamp, requestCounter++));

        ScoringRequest storage req = requests[requestId];
        req.coordX = _coordX;
        req.coordY = _coordY;
        req.nodes = _nodes;
        req.totalNodes = _nodes.length;
        req.respondedCount = 0;
        req.isComplete = false;

        // Llamar a cada nodo (asincrónico - no espera respuesta)
        for (uint256 i = 0; i < _nodes.length; i++) {
            INodeScoring(_nodes[i]).requestScore(requestId, _coordX, _coordY);
        }

        emit ScoringRequested(requestId, _coordX, _coordY, _nodes.length);
        return requestId;
    }

    // 2. Callback: Los nodos llaman esto cuando tienen el score listo
    function submitScore(bytes32 _requestId, uint256 _score) external {
        ScoringRequest storage req = requests[_requestId];

        require(req.totalNodes > 0, "Invalid request ID");
        require(!req.hasResponded[msg.sender], "Node already responded");
        require(!req.isComplete, "Request already completed");

        // Guardar score del nodo
        req.scores[msg.sender] = _score;
        req.hasResponded[msg.sender] = true;
        req.respondedCount++;

        emit ScoreReceived(_requestId, msg.sender, _score);

        // 3. Si todos respondieron, calcular promedio automáticamente
        if (req.respondedCount == req.totalNodes) {
            calculateAverage(_requestId);
        }
    }

    // 4. Calcular promedio cuando todos los nodos respondieron
    function calculateAverage(bytes32 _requestId) public {
        ScoringRequest storage req = requests[_requestId];

        require(req.totalNodes > 0, "Invalid request ID");
        require(!req.isComplete, "Already calculated");
        require(req.respondedCount == req.totalNodes, "Not all nodes responded yet");

        uint256 sum = 0;
        for (uint256 i = 0; i < req.nodes.length; i++) {
            sum += req.scores[req.nodes[i]];
        }

        req.averageScore = sum / req.totalNodes;
        req.isComplete = true;

        emit AverageCalculated(_requestId, req.averageScore);
    }

    // Funciones auxiliares para consultar estado
    function getRequestStatus(bytes32 _requestId)
        external
        view
        returns (uint256 responded, uint256 total, uint256 average, bool complete)
    {
        ScoringRequest storage req = requests[_requestId];
        return (req.respondedCount, req.totalNodes, req.averageScore, req.isComplete);
    }

    function getNodeScore(bytes32 _requestId, address _node)
        external
        view
        returns (uint256)
    {
        return requests[_requestId].scores[_node];
    }

    function hasNodeResponded(bytes32 _requestId, address _node)
        external
        view
        returns (bool)
    {
        return requests[_requestId].hasResponded[_node];
    }
}