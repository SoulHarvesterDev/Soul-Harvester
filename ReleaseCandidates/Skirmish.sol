// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Skirmish is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public manager;

    IERC20 public token;

    uint256 public totalVotes;
    uint256 public distribution_Vessel;
    uint256 public distribution_Team;
    uint256 public voting_bonus_OG; 
    uint256 public voteFinishTime;
    uint256 public season;

    address public teamAddress;
    address public vesselAddress;
    address public ogNFTAddress;
    
    bool public votingActive;
    bool public resetted;

    mapping(address => uint256) public votes;

    struct historyValues {
        uint256 season;
        address winner;
        uint256 totalSeasonVotes;
        uint256 voterCount;
        uint256 winnerShare;
    }
    historyValues[] public seasonHistory;

    struct activeVoter {
        address _voter;
        address _nominee;
        uint256 _votes;
    }
    activeVoter[] public voter;

    struct collection{
        uint256 votesApplied;
        bool isNominee;
        bool hasWon;
    }

    mapping(address => collection) public collectionInformation;
    address[] public listOfNominees;

    event VotesApplied(address indexed account, uint256 amount, address selection);

    constructor(
        IERC20 _token, 
        address _vesselAddress, 
        address _teamAddress, 
        address _ogNFTAddress 
        ) {
        token = _token;

        distribution_Vessel = 50000;    // value/100000
        distribution_Team = 30000;      // value/100000
        ogNFTAddress = _ogNFTAddress;               
        voting_bonus_OG = 110000;         // value/100000

        // distribution_Vessel = 50000;          // value/100000 (e.g. 50000/100000 = 50.000%)
        // distribution_Team = 30000;           // value/100000 (e.g. 30000/100000 = 30.000%)
        // ogNFTAddress = 0x0fE3552D5073A92A9021003042900aFaD3490bd9;
        // voting_bonus_OG = 110000;            // value/100000 (e.g. 110000/100000 = 110.000%)

        teamAddress = _teamAddress;
        vesselAddress = _vesselAddress;
        season = 0;
        resetted = true;
        votingActive = false;

        manager = msg.sender;

    } 

    function startVoting() public onlyOwnerOrManager {
        require(listOfNominees.length >= 2, "At least 2 Nominees have to be listed!");
        require(resetted, "List of nominees has to get resetted first!");

        voteFinishTime = block.timestamp + 7 days;
        totalVotes = 0;

        resetted = false;
        votingActive = true;
    }
    function finishVoting() public onlyOwnerOrManager {
        require(votingActive, "Voting is not live yet!");
        require(block.timestamp >= voteFinishTime, "Voting still running!");

        if (totalVotes > 0){
            uint256 votingResult = 0;
            uint256 share;
            address seasonWinner;

            for(uint256 i = 0; i < listOfNominees.length; i++){

                address nominee = listOfNominees[i];

                if(votingResult < collectionInformation[nominee].votesApplied){
                    votingResult = collectionInformation[nominee].votesApplied;
                    seasonWinner = nominee;
                }
            }

            share = votingResult * 100000 / totalVotes;
            seasonHistory.push(historyValues(season,seasonWinner,totalVotes,voter.length,share));
            season++;
            collectionInformation[seasonWinner].hasWon = true;
            
            uint256 amount = token.balanceOf(address(this));
            uint256 tokenForVessel = amount * distribution_Vessel / 100000;
            uint256 tokenForTeam = amount * distribution_Team / 100000;
            uint256 tokenForBurn = amount - tokenForTeam - tokenForVessel;

            // Distribute tokens
            token.safeTransfer(address(0), tokenForBurn);
            token.safeTransfer(teamAddress, tokenForTeam);
            token.safeTransfer(vesselAddress, tokenForVessel);        


        }
        for(uint256 i = 0; i < listOfNominees.length; i++){
            collectionInformation[listOfNominees[i]].votesApplied = 0;
            collectionInformation[listOfNominees[i]].isNominee = false;
        }

        delete voter;
        delete listOfNominees;
        votingActive = false;
        resetted = true;
    }
    function manuallyEndSeason() public onlyOwnerOrManager {
        require(block.timestamp <= voteFinishTime, "Voting has already ended!");
        voteFinishTime = block.timestamp;
    }

    function voteForNominee(uint256 amount, address nominee) public nonReentrant whenNotPaused{
        require(votingActive, "Voting is not live yet!");
        require(collectionInformation[nominee].isNominee, "NFT contract is not a nominee!");
        require(block.timestamp <= voteFinishTime, "Voting has already ended!");
        require(amount > 0, "Amount must be greater than zero");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient LP token balance");
        
        uint256 votingPower = amount;

        if(IERC721(ogNFTAddress).balanceOf(msg.sender) > 0){votingPower = votingPower * voting_bonus_OG / 100000;}

        votes[msg.sender] += votingPower;
        totalVotes += votingPower;
        token.safeTransferFrom(msg.sender, address(this), amount);
        
        collectionInformation[nominee].votesApplied += votingPower;

        voter.push(activeVoter(msg.sender,nominee,votingPower));

        uint256 ratio = votingPower * 100 / totalVotes;

        if(voteFinishTime - block.timestamp <= 3 days){
            if(ratio >= 33){
                voteFinishTime = block.timestamp + 3 days;
            }
        }

        emit VotesApplied(msg.sender, votingPower, nominee);
    }

    function addNominee(address nominee) public onlyOwnerOrManager {
        require(!votingActive, "Voting is already active!");
        require(resetted, "Data from last season are not yet resetted!");
        require(!collectionInformation[nominee].isNominee, "NFT contract is already nominee!");
        require(!collectionInformation[nominee].hasWon, "NFT contract has already won once!");
        require(listOfNominees.length < 3, "Already 3 Nominees are listed!");

        collectionInformation[nominee].votesApplied = 0;
        collectionInformation[nominee].isNominee = true;
        listOfNominees.push(nominee);
    }

    function getNominees() public view returns (address[] memory _nominees){
        require(listOfNominees.length >= 1, "At least 2 Nominees have to be listed!");
        require(votingActive, "Voting is not live yet!");

        return listOfNominees;
    }
    function getSeasonHistory() public view returns (historyValues[] memory _history){
        require(seasonHistory.length >= 1, "At least one season has to be concluded!");
       
        return seasonHistory;
    }
    function getSeasonVoter() public view returns (activeVoter[] memory _seasonVoter){
        require(votingActive, "Voting is not live yet!");
        require(voter.length >= 1, "At least someone should vote first!");
       
        return voter;
    }
    function getShareForNominee(address _nominee) public view returns (uint256){
        require(listOfNominees.length >= 2, "At least 2 Nominees have to be listed!");
        require(votingActive, "Voting is not live yet!");
        require(collectionInformation[_nominee].isNominee, "Requested collection is not a nominee!");

        uint256 share = collectionInformation[_nominee].votesApplied * 100000 / totalVotes;
        return share;
    }


    function setTokenAddress(address _tokenAddress) public onlyOwner {
        token = IERC20(_tokenAddress);
    }

    function setTeamAddress(address _teamAddress) public onlyOwner {
        teamAddress = _teamAddress;
    }  

    function setTeamPortion(uint256 _teamPortion) public onlyOwner {
        distribution_Team = _teamPortion;       // value / 100000
    }

    function setVesselAddress(address _vesselAddress) public onlyOwner {
        vesselAddress = _vesselAddress;
    } 

    function setVesselPortion(uint256 _vesselPortion) public onlyOwner {
        distribution_Vessel = _vesselPortion;     // value / 100000
    }

    function setOGNFTAddress(address _ogNFTAddress) public onlyOwner {
        ogNFTAddress = _ogNFTAddress;
    }
    
    function setOGBonus(uint256 _bonus_OG) public onlyOwner {
        voting_bonus_OG = _bonus_OG;            // value / 100000
    }

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
    
    function changeManager(address newManager) public onlyOwner {
    manager = newManager;
    }
    }
