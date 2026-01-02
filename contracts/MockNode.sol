// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

interface INodeScoring {
     function requestScore(bytes32 _requestId, uint256 _coordX, uint256 _coordY, address _mainNode) external;
}

interface IMainNode {
     function submitScore(bytes32 _requestId, uint256 score) external;
}

contract MockScoringNode is INodeScoring {

    function requestScore(bytes32 _requestId, uint256 _coordX, uint256 _coordY, address _mainNode) external{
        emit DebugRequestId(_requestId, _coordX, _coordY);
        // Mock implementation - in real scenario, this would calculate a score
        // and call back to the DemoScoringNodes contract
        uint256 score = (uint256(keccak256(abi.encodePacked(block.number, msg.sender, _requestId))) % 41) + 60; // Mock score
        // Call back to the main node with the score
        IMainNode(_mainNode).submitScore(_requestId, score);
    }
    event DebugRequestId(bytes32 indexed requestId, uint256 coordX, uint256 coordY);
}