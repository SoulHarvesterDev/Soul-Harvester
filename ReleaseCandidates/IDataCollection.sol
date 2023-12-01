// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;


interface IDataCollection {
    struct User{
        address userAddress;
        uint256 allTimeReceived;
        uint256 allTimeBurnedNFT;
    }    

    //Setter
    function updateCollectionInformation(address _collection, uint256 _timeElapsed, uint256 _nrOfTokenBurned, uint256 _tokenReceived) external;
    function updateUserValues(address _userAddress, uint256 _incAllTimeReceived, uint256 _incAllTimeBurnedNFT) external;    
    //Getter
    function isWhitelisted(address _address) external view returns (bool);
    function getLastBurned(address _address) external view returns (uint256);
    function getShare(address _address) external view returns (uint256);
    function getAvailable(address _address) external view returns (uint256);
    function getAlreadyBurned(address _address) external view returns (uint256);

    function getUser(uint256 index) external view returns (address, uint256, uint256);
    function getTopUsersByAllTimeBurnedNFT(uint256 numberOfTopUsers) external view returns (User[] memory);
    function getTopUsersByAllTimeReceived(uint256 numberOfTopUsers) external view returns (User[] memory);
}