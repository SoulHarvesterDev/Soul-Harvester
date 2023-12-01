// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "ISoulStone.sol";


contract Interaction {

    ISoulStone public Minter;

    constructor(){

        Minter = ISoulStone(0x34E279B654e36602b702FA187133506120E8bd91);
    }

    function changeMinterAddr(address _newMinterAddr) public payable {
       Minter = ISoulStone(_newMinterAddr);
    }

    function doHarvest(address _to) public {
        Minter.mintNext(_to);
    }
}