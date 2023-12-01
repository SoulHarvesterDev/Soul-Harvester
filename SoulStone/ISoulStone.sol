// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;


interface ISoulStone {
    /**
     * @dev Mints the next Soul Stone
    */
    function mintNext(address to) external;
    /**
     * @dev returns the actual bonus value for a Soul Stone
    */    
    function getBonusValueHarvest(address _wallet) external view returns (uint256);
    /**
     * @dev returns the actual bonus value for a Soul Stone
    */    
    function getBonusValueSkirmish(address _wallet) external view returns (uint256);
    /**
     * @dev checks a Wallet for a Soul Stone
    */    
    function hasSoulStone(address _wallet) external view returns (bool);

}   
