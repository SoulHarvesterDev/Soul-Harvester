// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;


interface IHarvester {



    function getUser(uint256) external view returns (address, uint256, uint256);
    function numberOfUsers() external view returns (uint256);
    function getWhitelist() external view returns(address[]memory);
    function collectionInformation(address) external view returns(bool, uint256, uint256, uint256, uint256, uint256, uint256, uint256);

}