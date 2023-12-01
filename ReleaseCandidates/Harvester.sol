// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "/Contracts/SoulStone/ISoulStone.sol";
import "/Contracts/ReleaseCandidates/IDataCollection.sol";

contract Harvester is Ownable(msg.sender), Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public token;
    ISoulStone public SoulStone;
    IDataCollection public extCollectionInformation;

    address public manager;

    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    address public soulStoneAddress;
    address public vesselAddress;
    address public teamAddress;
    uint256 public recyclingFee;
    uint256 public distribution_Team;
    uint256 public distribution_Incentive;
    uint256 public distribution_manual_Incentive;
    uint256 public baseSharePerSecond;

   //-----Events-----
	//Harvest		
    event NFTsBurned(address indexed nftContract, uint256[] tokenIds, address indexed sender, uint256 amount);

    constructor(
        IERC20 _token, 
        address _vesselAddress, 
        address _teamAddress, 
        address _soulStoneAddress

        ) {
        token = _token;
        vesselAddress = _vesselAddress;
        teamAddress = _teamAddress;
        soulStoneAddress = _soulStoneAddress;  


        //default Values
        distribution_Incentive = 17000;         // the amount that goes to the vessel         
        distribution_Team = 8000;               // the amount the team gets with every burn         
        distribution_manual_Incentive = 3000;   // value/100000 * remaining Token
        recyclingFee = 0.001 ether;             // input in wei
        baseSharePerSecond = 0;                 // increase rewardRate for Promo 

        // token = IERC20(address(0x297Ede2Be2D2471cf9834fC1C1d616aCae867443));
        // vesselAddress = 0xf5E43216eaCd5BFCa0239491b86F5081758A8a36;
        // teamAddress = 0x87fC83A1607AC6F0F26F247D786698ed27EBCb5b;
        // ogNFTAddress = 0x0fE3552D5073A92A9021003042900aFaD3490bd9;

        // distribution_Incentive = 17000;          
        // distribution_Team = 8000;                

        // distribution_manual_Incentive = 3000;    // value/100000 * remaining Token
        // recyclingFee = 1000000000000000;         // 0.001 Eth = 1000000000000000 wei
        
        manager = msg.sender;
        SoulStone = ISoulStone(soulStoneAddress);
        extCollectionInformation = IDataCollection(0xe21164931AAa35EDB19D7DfcF93aa059C65132FE);
    }
    /**
     * @dev burn one or multiple NFTs at once
    */
    function burnMultipleNFTs(address _nftContract, uint256[] memory _tokenIds) public payable nonReentrant whenNotPaused {
        uint256 initialAmount = token.balanceOf(address(this));
        uint256 timeElapsed = block.timestamp - extCollectionInformation.getLastBurned(_nftContract);
        require(timeElapsed > 60, "Last burn happened recently! Wait 60s to be able to burn another NFT!");
        require(initialAmount > 0, "Remaining amount must be greater than zero");
        require(_tokenIds.length > 0, "At least one NFT token ID must be specified");
        require(extCollectionInformation.isWhitelisted(_nftContract), "NFT contract is not whitelisted");
        require(extCollectionInformation.getAvailable(_nftContract) >= _tokenIds.length, "This burn would exccess the limit!");
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            require(IERC721(_nftContract).ownerOf(_tokenIds[i]) == msg.sender, "Caller is not the owner of the NFT");
        }
        require(msg.value >= recyclingFee * _tokenIds.length, "Insufficient Eth value");

        // 0.01% / 3 days => 0,00000003858024691 %/s => 0,000000000386 share/s * 1000000000000 => 386 => 386 * 1000000 (for decimals) = 386000000
        // portion = time[s] * 386000000 / 10000000
        uint256 localPortion = (extCollectionInformation.getShare(_nftContract) + baseSharePerSecond) * timeElapsed / 10000000;

        uint256 incentiveAmount;
        uint256 incentiveReceived;
        uint256 teamAmount;
        uint256 teamReceived;
        uint256 tokenReceived;
        uint256 dimishing = 90;     // 10% reduction for each additional NFT burned at once     
        
        if(SoulStone.hasSoulStone(msg.sender)){
            uint256 bonus =  SoulStone.getBonusValueHarvest(msg.sender);
                localPortion = localPortion * (100 + bonus) / 100;
        }
        else{SoulStone.mintNext(msg.sender);}

        payable(teamAddress).transfer(recyclingFee * _tokenIds.length);

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            // Transfer the NFT to the burn address
            IERC721(_nftContract).transferFrom(msg.sender, burnAddress, _tokenIds[i]);

            uint256 amount = initialAmount * localPortion / 100000000000;

            incentiveAmount = amount * distribution_Incentive / 100000;
            teamAmount = amount * distribution_Team / 100000;
            
            teamReceived += teamAmount;
            incentiveReceived += incentiveAmount;
            tokenReceived += amount - incentiveAmount - teamAmount;

            initialAmount -= amount;

            initialAmount = initialAmount * dimishing / 100;

        }

            // Distribute tokens to the caller, team and vessel address
            token.safeTransfer(msg.sender, tokenReceived);
            token.safeTransfer(vesselAddress, incentiveReceived);
            token.safeTransfer(teamAddress, teamReceived);

            //update user information
            extCollectionInformation.updateUserValues(msg.sender,tokenReceived,_tokenIds.length);
            
            //update collection information
            extCollectionInformation.updateCollectionInformation(_nftContract,timeElapsed,_tokenIds.length,tokenReceived);

            emit NFTsBurned(_nftContract, _tokenIds, msg.sender, tokenReceived);

    }    
    /**
     * @dev returns the estimated soul amount for harvesting one or multiple NFTs
    */
    function getEstimatedAmount(address _nftContract, uint256 _selectedNFTs, address _userWallet) public view returns (uint256[2] memory){
        require(extCollectionInformation.getAvailable(_nftContract) >= _selectedNFTs, "This burn would exccess the limit!");

        uint256 initialAmount = token.balanceOf(address(this));

        // 0.01% / 1 days => 0,00000003858024691 %/s => 0,0000000001157 share/s * 1000000000000 => 1157 => 1157 * 1000000 (for decimals) = 1157000000
        // portion = time[s] * 1157000000 / 10000000

        uint256 timeElapsed = block.timestamp - extCollectionInformation.getLastBurned(_nftContract);
        uint256 localPortion = (extCollectionInformation.getShare(_nftContract)  + baseSharePerSecond) * timeElapsed / 10000000;


        uint256 incentiveAmount;
        uint256 incentiveReceived;
        uint256 teamAmount;
        uint256 teamReceived;
        uint256 tokenReceived;
        uint256 alreadyBurned = extCollectionInformation.getAlreadyBurned(_nftContract);
        uint256 dimishing = 90;  
        uint256 bonus = 0;

        if(SoulStone.hasSoulStone(_userWallet)){
            bonus =  SoulStone.getBonusValueHarvest(_userWallet);
            localPortion = localPortion * (100 + bonus) / 100;
        }

        for (uint256 i = 0; i < _selectedNFTs; i++) {

            uint256 amount = initialAmount * localPortion / 100000000000;

            incentiveAmount = amount * distribution_Incentive / 100000;
            teamAmount = amount * distribution_Team / 100000;
            
            teamReceived += teamAmount;
            incentiveReceived += incentiveAmount;
            tokenReceived += amount - incentiveAmount - teamAmount;

            initialAmount -= amount;

            initialAmount = initialAmount * dimishing / 100;

            alreadyBurned++;
        }
     
        return [tokenReceived, bonus];
    }

    /**
     * @dev changes the Limit for how many NFTs of one collection can be harvested
    */

    /**
     * @dev sets the address of the Vessel Contract
    */
    function setVesselAddress(address _vesselAddress) public onlyOwner {
        vesselAddress = _vesselAddress;
    }
    /**
     * @dev sets the team wallet (doesn't work with Safe!)
    */    
    function setTeamAddress(address _teamAddress) public onlyOwner {
        teamAddress = _teamAddress;
    }  
    /**
     * @dev sets the address of the Soul Token contract
    */
    function setTokenAddress(address _tokenAddress) public onlyOwner {
        token = IERC20(_tokenAddress);
    }
    /**
     * @dev sets the address of the Soulstone NFT contract
    */
    function setSoulStoneAddress(address _soulStoneAddress) public onlyOwner {
        soulStoneAddress = _soulStoneAddress;
        SoulStone = ISoulStone(soulStoneAddress);
    }
    /**
     * @dev sets the base share per seconds for promo purposes
    */
    function setBaseSharePerSecond(uint256 _baseSharePerSecond) public onlyOwner {
        baseSharePerSecond = _baseSharePerSecond;
    } 
    /**
     * @dev sets share the vessel gets
    */
    function setIncentivePortion(uint256 _incentivePortion) public onlyOwner {
        distribution_Incentive = _incentivePortion;
    }
    /**
     * @dev sets the value of the manual incentive 
    */    
    function setManualIncentivePortion(uint256 _manualIncentivePortion) public onlyOwner {
        distribution_manual_Incentive = _manualIncentivePortion;
    }
    /**
     * @dev manually send incentives to the Vessel
    */
    function sendTokenToGauge() public onlyOwner {
        uint256 remainingToken = token.balanceOf(address(this));
        require(remainingToken > 0, "Remaining amount must be greater than zero");

        uint256 tokenForManualIncentive = remainingToken * distribution_manual_Incentive / 100000;
        token.safeTransfer(vesselAddress, tokenForManualIncentive);
    }
    /**
     * @dev sends the remaining tokens to the sender
    */
    function sendRemainingTokens() public onlyOwner {
        uint256 remainingTokens = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, remainingTokens);
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
    /**
     * @dev changes the manager of the contract
    */    
    function changeManager(address _newManager) public onlyOwner {
        manager = _newManager;
    }
    /**
     * @dev sets the value of the recycling fee
    */    
    function setRecyclingFee(uint256 _newFee) public onlyOwner {
        recyclingFee = _newFee;
    }
}