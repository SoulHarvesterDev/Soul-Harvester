// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;


interface ISkirmish {

    function getSeasonHistory(uint256 _index) external view returns (uint256, address, uint256, uint256, uint256);
    function season() external view returns (uint256);
}