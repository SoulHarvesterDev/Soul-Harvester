// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Harvester is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public token;

    address public manager;

    struct user{
        uint256  allTimeReceived;
        uint256  allTimeBurnedNFT;
    }    
    mapping(address => user) public userInformation;

    struct collection{
        bool isWhitelisted;
        uint256 alreadyBurned;
        uint256 alreadyReceivedToken;
        uint256 limit;
        uint256 available;
        uint256 harvestingEfficiency;
        uint256 dimishingFactor;
    }
    mapping(address => collection) public collectionInformation;

    //
    address[] public whitelistedContracts;
    address public burnAddress;
    address public gaugeAddress;
    address public teamAddress;
    uint256 public portion;
    uint256 public distribution_Team;
    uint256 public distribution_Incentive;
    uint256 public distribution_manual_Incentive;
    uint256 public distribution_bonus_OG;

    address public ogNFTAddress;
			
    event NFTsBurned(address indexed nftContract, uint256[] tokenIds, address indexed sender, uint256 amount);

    constructor(
        IERC20 _token, 
        address _burnaddress, 
        address _gaugeAddress, 
        address _teamAddress, 
        uint256 _portion, 
        uint256 _distribution_Incentive, 
        uint256 _distribution_Team, 
        uint256 _distribution_manual_Incentive,
        address _ogNFTAddress,
        uint256 _distribution_bonus_OG 
        ) {
        token = _token;
        burnAddress = _burnaddress;
        gaugeAddress = _gaugeAddress;
        teamAddress = _teamAddress;
        portion = _portion;                                             // value/100000 * remaining Token
        distribution_Incentive = _distribution_Incentive;               // value/100000 * portion
        distribution_Team = _distribution_Team;                         // value/100000 * portion

        distribution_manual_Incentive = _distribution_manual_Incentive; // value/100000 * remaining Token
        ogNFTAddress = _ogNFTAddress;
        distribution_bonus_OG = _distribution_bonus_OG;                 // value/100000 * portion

        // token = IERC20(address(0xc0C16B8e166D2b576f1cDA822aE24E2e8d06B49f));
        // burnAddress = 0x000000000000000000000000000000000000dEaD;
        // gaugeAddress = 0xd75CD7323FDA26F23361250E7e9A558C14E89d84;
        // teamAddress = 0x87fC83A1607AC6F0F26F247D786698ed27EBCb5b;
        // ogNFTAddress = 0x0fE3552D5073A92A9021003042900aFaD3490bd9;

        // portion = 10;                            // value/100000 * remaining Token
        // distribution_Incentive = 17000;          // value/100000 * portion
        // distribution_Team = 8000;                // value/100000 * portion

        // distribution_manual_Incentive = 3000;    // value/100000 * remaining Token
        // distribution_bonus_OG = 110000;          // value/100000 * portion


    }

    function burnMultipleNFTs(address _nftContract, uint256[] memory _tokenIds) public nonReentrant whenNotPaused {
        uint256 initialAmount = token.balanceOf(address(this));
        require(initialAmount > 0, "Remaining amount must be greater than zero");
        require(_tokenIds.length > 0, "At least one NFT token ID must be specified");
        require(collectionInformation[_nftContract].isWhitelisted, "NFT contract is not whitelisted");
        require(collectionInformation[_nftContract].available >= _tokenIds.length, "This burn would exccess the limit!");
        require(collectionInformation[_nftContract].harvestingEfficiency > 0,"Already too many NFTs of this collection were burned!");
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            require(IERC721(_nftContract).ownerOf(_tokenIds[i]) == msg.sender, "Caller is not the owner of the NFT");
        }
        uint256 localPortion = portion;
        uint256 incentiveAmount;
        uint256 incentiveReceived;
        uint256 teamAmount;
        uint256 teamReceived;
        uint256 tokenReceived;
        
        if(IERC721(ogNFTAddress).balanceOf(msg.sender) > 0){localPortion = portion * distribution_bonus_OG / 100000;}

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            // Transfer the NFT to the burn address
            IERC721(_nftContract).transferFrom(msg.sender, burnAddress, _tokenIds[i]);

            uint256 amount = initialAmount * localPortion / 100000;

            amount = amount * collectionInformation[_nftContract].harvestingEfficiency / 100000;

            incentiveAmount = amount * distribution_Incentive / 100000;
            teamAmount = amount * distribution_Team / 100000;
            
            teamReceived += teamAmount;
            incentiveReceived += incentiveAmount;
            tokenReceived += amount - incentiveAmount - teamAmount;

            initialAmount -= amount;
            collectionInformation[_nftContract].alreadyBurned++;
            collectionInformation[_nftContract].harvestingEfficiency = collectionInformation[_nftContract].harvestingEfficiency * collectionInformation[_nftContract].dimishingFactor / 100000;
        }

            // Distribute tokens to the caller, team and Gauge address
            token.safeTransfer(msg.sender, tokenReceived);
            token.safeTransfer(gaugeAddress, incentiveReceived);
            token.safeTransfer(teamAddress, teamReceived);

            //update user information
            userInformation[msg.sender].allTimeReceived += tokenReceived;
            
            //update collection information
            collectionInformation[_nftContract].alreadyReceivedToken += tokenReceived;
            collectionInformation[_nftContract].available = collectionInformation[_nftContract].limit - collectionInformation[_nftContract].alreadyBurned;
            emit NFTsBurned(_nftContract, _tokenIds, msg.sender, tokenReceived);

    }    

    function getEstimatedAmount(address _nftContract, uint256 _selectedNFTs, address _userWallet) public view returns (uint256 _estimation){
        uint256 efficiency = collectionInformation[_nftContract].harvestingEfficiency;

        require(efficiency > 0,"Already too many NFTs of this collection were burned!");
        require(collectionInformation[_nftContract].available >= _selectedNFTs, "This burn would exccess the limit!");

        uint256 initialAmount = token.balanceOf(address(this));
        uint256 localPortion = portion;
        uint256 incentiveAmount;
        uint256 incentiveReceived;
        uint256 teamAmount;
        uint256 teamReceived;
        uint256 tokenReceived;
        uint256 alreadyBurned = collectionInformation[_nftContract].alreadyBurned;
        uint256 dimishing = collectionInformation[_nftContract].dimishingFactor;

        if(IERC721(ogNFTAddress).balanceOf(_userWallet) > 0){localPortion = portion * distribution_bonus_OG / 100000;}

        for (uint256 i = 0; i < _selectedNFTs; i++) {

            uint256 amount = initialAmount * localPortion / 100000;

            amount = amount * efficiency / 100000;

            incentiveAmount = amount * distribution_Incentive / 100000;
            teamAmount = amount * distribution_Team / 100000;
            
            teamReceived += teamAmount;
            incentiveReceived += incentiveAmount;
            tokenReceived += amount - incentiveAmount - teamAmount;

            initialAmount -= amount;
            alreadyBurned++;
            efficiency = efficiency * dimishing / 100000;

        }
     
        return tokenReceived;
    }
 
    function addToWhitelist(address _nftContract, uint256 _limit, uint256 _harvestingEfficiency, uint256 _dimishingFactor) public onlyOwnerOrManager {
        require(!collectionInformation[_nftContract].isWhitelisted, "NFT contract is already whitelisted");

        collectionInformation[_nftContract].isWhitelisted = true;
        collectionInformation[_nftContract].limit = _limit;
        collectionInformation[_nftContract].available = collectionInformation[_nftContract].limit - collectionInformation[_nftContract].alreadyBurned;
        collectionInformation[_nftContract].harvestingEfficiency = _harvestingEfficiency;
        collectionInformation[_nftContract].dimishingFactor = _dimishingFactor;

        whitelistedContracts.push(_nftContract);

        // Defaults
        // _limit = 1000
        // _harvestingEfficiency = 100000
        // _dimishingFactor = 99500

    }
    function getWhitelist() public view returns (address[] memory _whitelistedContracts){
       
        return whitelistedContracts;
    }   

    function changeLimit(address _nftContract, uint256 _limit) public onlyOwnerOrManager {
        require(collectionInformation[_nftContract].isWhitelisted, "NFT contract is not whitelisted");
        require(_limit >= collectionInformation[_nftContract].alreadyBurned, "Limit would be less than NFTs alread been burned!");
        
        collectionInformation[_nftContract].limit = _limit;
    }

    function removeFromWhitelist(address _nftContract) public onlyOwnerOrManager {
        require(collectionInformation[_nftContract].isWhitelisted, "NFT contract is not whitelisted");
        collectionInformation[_nftContract].isWhitelisted = false;

        uint256 index;

        for(uint256 i = 0; i < whitelistedContracts.length; i++){
            if (_nftContract == whitelistedContracts[i]){
                index = i;
                break;
            }
        }

        whitelistedContracts[index] = whitelistedContracts[whitelistedContracts.length - 1];
        whitelistedContracts.pop();
    }

    function setGaugeAddress(address _gaugeAddress) public onlyOwner {
        gaugeAddress = _gaugeAddress;
    }
    
    function setTeamAddress(address _teamAddress) public onlyOwner {
        teamAddress = _teamAddress;
    }  

    function setTokenAddress(address _tokenAddress) public onlyOwner {
        token = IERC20(_tokenAddress);
    }

    function setPortion(uint256 _portion) public onlyOwner {
        portion = _portion;
    }
    
    function setOGNFTAddress(address _ogNFTAddress) public onlyOwner {
        ogNFTAddress = _ogNFTAddress;
    }

    function setOGBonus(uint256 _bonus_OG) public onlyOwner {
        distribution_bonus_OG = _bonus_OG;
    }

    function setIncentivePortion(uint256 _incentivePortion) public onlyOwner {
        distribution_Incentive = _incentivePortion;
    } 

    function setManualIncentivePortion(uint256 _manualIncentivePortion) public onlyOwner {
        distribution_manual_Incentive = _manualIncentivePortion;
    }
    
    function setDimishingFactor(address _nftContract, uint256 _dimishingFactor) public onlyOwner {
        require(collectionInformation[_nftContract].isWhitelisted, "NFT contract is not whitelisted");

        collectionInformation[_nftContract].dimishingFactor = _dimishingFactor;
    }

    function sendRemainingTokens() public onlyOwner {
        uint256 remainingTokens = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, remainingTokens);
    }

    function sendTokenToGauge() public onlyOwner {
        uint256 remainingToken = token.balanceOf(address(this));
        require(remainingToken > 0, "Remaining amount must be greater than zero");

        uint256 tokenForManualIncentive = remainingToken * distribution_manual_Incentive / 100000;
        token.safeTransfer(gaugeAddress, tokenForManualIncentive);
    }

    function transferOwnership(address _newOwner) public override onlyOwner {
        _transferOwnership(_newOwner);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
        
    modifier onlyOwnerOrManager() {
        address _owner = owner();
        require(msg.sender == _owner || msg.sender == manager, "You are neither the owner nor the manager!");
        _;
    }    
    
    function changeManager(address newManager) public onlyOwner {
        manager = newManager;
    }    
}