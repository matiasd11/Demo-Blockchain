// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

interface INodeScoring {
    function getScore() external view returns (uint256);
}

contract DemoNodes {

    uint256 public scoring;

    address[] public nodeAddresses;
    mapping(address => uint256) public nodeScore;

    function callNodes(address[] calldata _address) public {
        for (uint256 i = 0; i < _address.length; i++) {
            callNodeScoring(_address[i]);
        }
    }

    function submitScore(uint256 _score, address _address) public {
        if (nodeScore[_address] == 0) {
            nodeAddresses.push(_address);
        }
        nodeScore[_address] = _score;
    }

    function calculateAverage() public{
        uint256 sum = 0;
        for (uint256 i = 0; i < nodeAddresses.length; i++) {
            sum += nodeScore[nodeAddresses[i]];
        }
        scoring = sum / nodeAddresses.length;
    }

    function callNodeScoring(address _nodeAddress) public {
        INodeScoring nodeContract = INodeScoring(_nodeAddress);
        uint256 score = nodeContract.getScore();
    }
}