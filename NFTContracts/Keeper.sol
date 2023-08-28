// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";


contract Keeper is ERC721, Pausable, Ownable {
    using StringsUpgradeable for uint256;

    string public baseURI = "ipfs://QmQqCgfvADwEHKCdDGBbD1dH4DdgzgUB4ZRyyGrm7eiu3d/";
    uint256 private id;

    constructor() ERC721("Keeper", "KEEPER") {}

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
    function mintNext(address to) public onlyOwner{
        id++;
        _safeMint(to, id);

    }
    
    function mintBatch(address[] memory inputArray) public onlyOwner{

        for (uint256 i = 0; i < inputArray.length; i++) {
            id++;
             _safeMint(inputArray[i], id);
         }   
    }
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "URI query for nonexistent token");

        return bytes(baseURI).length > 0 ?
            string(abi.encodePacked(
                baseURI,
                _tokenId.toString(),
                ".json"
            ))
            : "";
    }

    function setURI(string memory _uri) external onlyOwner{
        baseURI = _uri;
    }
    
    function totalSupply() public view returns(uint256){
        return id;
    }

    }
