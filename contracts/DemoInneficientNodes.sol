// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

/**
 * @title AIOracle_OnChainConsensus
 * @dev Versión INEFICIENTE: Cada nodo envía score on-chain y promedio se calcula on-chain
 * @notice DEMO: Comparación de costos de gas vs versión DON
 */
contract AIOracle_OnChainConsensus {
    
    struct NodeScore {
        uint256 score;
        uint256 timestamp;
        bool hasSubmitted;
    }
    
    struct Request {
        uint256 projectId;
        uint256 timestamp;
        uint256 nodeCount;
        uint256 totalScore;
        uint256 averageScore;
        bool isFinalized;
    }
    
    // requestId => nodeAddress => NodeScore
    mapping(bytes32 => mapping(address => NodeScore)) public nodeScores;
    
    // requestId => Request
    mapping(bytes32 => Request) public requests;
    
    // Nodos autorizados
    mapping(address => bool) public authorizedNodes;
    address[] public nodeList; // Para iterar
    
    address public owner;
    uint256 public minNodes;
    uint256 public totalGasUsed; // Tracking de gas acumulado
    
    event RequestCreated(bytes32 indexed requestId, uint256 projectId);
    event ScoreSubmitted(bytes32 indexed requestId, address indexed node, uint256 score, uint256 gasUsed);
    event AverageCalculated(bytes32 indexed requestId, uint256 average, uint256 gasUsed);
    event NodeAuthorized(address indexed node);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Solo owner");
        _;
    }
    
    modifier onlyAuthorizedNode() {
        require(authorizedNodes[msg.sender], "Nodo no autorizado");
        _;
    }
    
    constructor(uint256 _minNodes) {
        owner = msg.sender;
        minNodes = _minNodes;
    }
    
    function authorizeNode(address _node) external onlyOwner {
        require(!authorizedNodes[_node], "Ya autorizado");
        authorizedNodes[_node] = true;
        nodeList.push(_node);
        emit NodeAuthorized(_node);
    }
    
    /**
     * @dev Crear nueva solicitud de scoring
     */
    function createRequest(uint256 _projectId) external onlyOwner returns (bytes32) {
        uint256 startGas = gasleft();
        
        bytes32 requestId = keccak256(abi.encodePacked(_projectId, block.timestamp, block.number));
        
        requests[requestId] = Request({
            projectId: _projectId,
            timestamp: block.timestamp,
            nodeCount: 0,
            totalScore: 0,
            averageScore: 0,
            isFinalized: false
        });
        
        uint256 gasUsed = startGas - gasleft();
        totalGasUsed += gasUsed;
        
        emit RequestCreated(requestId, _projectId);
        return requestId;
    }
    
    /**
     * @dev Cada nodo envía su score individualmente (COSTOSO)
     * @notice Cada transacción cuesta ~50,000-100,000 gas
     */
    function submitScore(bytes32 _requestId, uint256 _score) external onlyAuthorizedNode {
        uint256 startGas = gasleft();
        
        Request storage req = requests[_requestId];
        require(!req.isFinalized, "Request ya finalizado");
        require(!nodeScores[_requestId][msg.sender].hasSubmitted, "Ya enviaste tu score");
        
        // Guardar score del nodo
        nodeScores[_requestId][msg.sender] = NodeScore({
            score: _score,
            timestamp: block.timestamp,
            hasSubmitted: true
        });
        
        // Acumular para promedio
        req.totalScore += _score;
        req.nodeCount++;
        
        uint256 gasUsed = startGas - gasleft();
        totalGasUsed += gasUsed;
        
        emit ScoreSubmitted(_requestId, msg.sender, _score, gasUsed);
    }
    
    /**
     * @dev Calcular promedio on-chain (MUY COSTOSO)
     * @notice Itera sobre todos los nodos - gas aumenta linealmente con N nodos
     */
    function calculateAverage(bytes32 _requestId) external {
        uint256 startGas = gasleft();
        
        Request storage req = requests[_requestId];
        require(!req.isFinalized, "Ya finalizado");
        require(req.nodeCount >= minNodes, "Faltan nodos");
        
        // Calcular promedio
        req.averageScore = req.totalScore / req.nodeCount;
        req.isFinalized = true;
        
        uint256 gasUsed = startGas - gasleft();
        totalGasUsed += gasUsed;
        
        emit AverageCalculated(_requestId, req.averageScore, gasUsed);
    }
    
    /**
     * @dev Obtener score de un nodo específico
     */
    function getNodeScore(bytes32 _requestId, address _node) 
        external 
        view 
        returns (uint256 score, uint256 timestamp, bool submitted) 
    {
        NodeScore memory ns = nodeScores[_requestId][_node];
        return (ns.score, ns.timestamp, ns.hasSubmitted);
    }
    
    /**
     * @dev Obtener todos los scores de un request (COSTOSO en gas para lectura)
     */
    function getAllScores(bytes32 _requestId) 
        external 
        view 
        returns (address[] memory nodes, uint256[] memory scores) 
    {
        uint256 count = requests[_requestId].nodeCount;
        nodes = new address[](count);
        scores = new uint256[](count);
        
        uint256 index = 0;
        for (uint256 i = 0; i < nodeList.length && index < count; i++) {
            address node = nodeList[i];
            if (nodeScores[_requestId][node].hasSubmitted) {
                nodes[index] = node;
                scores[index] = nodeScores[_requestId][node].score;
                index++;
            }
        }
        
        return (nodes, scores);
    }
    
    function getRequest(bytes32 _requestId) 
        external 
        view 
        returns (
            uint256 projectId,
            uint256 nodeCount,
            uint256 averageScore,
            bool isFinalized
        ) 
    {
        Request memory req = requests[_requestId];
        return (req.projectId, req.nodeCount, req.averageScore, req.isFinalized);
    }
    
    function getTotalGasUsed() external view returns (uint256) {
        return totalGasUsed;
    }
    
    function resetGasCounter() external onlyOwner {
        totalGasUsed = 0;
    }
}