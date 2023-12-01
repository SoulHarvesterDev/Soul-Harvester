// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "/Contracts/SoulStone/ISoulStone.sol";
import "/Contracts/ReleaseCandidates/ISkirmish.sol";

contract Skirmish is Ownable(msg.sender), Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public manager;

    IERC20 public token;
    ISoulStone public SoulStone;
    ISkirmish public oldSkirmish;

    uint256 public totalVotes;
    uint256 public distribution_Vessel;
    uint256 public distribution_Team;
    uint256 public voting_bonus_OG; 
    uint256 public voteFinishTime;
    uint256 public season;

    address public teamAddress;
    address public vesselAddress;
    address public ogNFTAddress;
    address public soulStoneAddress;
    
    bool public votingActive;
    bool public resetted;
    bool public migrated;

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
        address _soulStoneAddress 
        ) {
        token = _token;
        soulStoneAddress = _soulStoneAddress;  

        distribution_Vessel = 50000;    // value/100000
        distribution_Team = 30000;      // value/100000
        voting_bonus_OG = 110000;         // value/100000

        // distribution_Vessel = 50000;          // value/100000 (e.g. 50000/100000 = 50.000%)
        // distribution_Team = 30000;           // value/100000 (e.g. 30000/100000 = 30.000%)
        // voting_bonus_OG = 110000;            // value/100000 (e.g. 110000/100000 = 110.000%)

        teamAddress = _teamAddress;
        vesselAddress = _vesselAddress;
        season = 0;
        resetted = true;
        votingActive = false;

        manager = msg.sender;
        SoulStone = ISoulStone(soulStoneAddress);
        oldSkirmish = ISkirmish(0xC86d739474C9c45007f41c99FE650FBc4372887a);
    } 

    function startVoting(uint256 daysActive ) public onlyOwnerOrManager {
        require(listOfNominees.length >= 2, "At least 2 Nominees have to be listed!");
        require(resetted, "List of nominees has to get resetted first!");
        require(daysActive > 0, "Duration has to be greater than 0!");

        voteFinishTime = block.timestamp + (daysActive * 1 days);
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

        if(SoulStone.hasSoulStone(msg.sender)){
            uint256 bonus = SoulStone.getBonusValueSkirmish(msg.sender);
            votingPower = votingPower * (100 + bonus) / 100;
        }

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

    function getEstimatedVotingPower(address wallet, uint256 amount) public view returns(uint256[2] memory){
        
        uint256 votingPower = amount;
        uint256 bonus = 0;

        if(SoulStone.hasSoulStone(wallet)){
            bonus = SoulStone.getBonusValueSkirmish(wallet);
            votingPower = votingPower *  (100 + bonus) / 100;
        }        

        return [votingPower, bonus];
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

    function getNominees() public view returns (address[] memory){
        require(listOfNominees.length >= 1, "At least 2 Nominees have to be listed!");
        require(votingActive, "Voting is not live yet!");

        return listOfNominees;
    }

    function getSeasonHistory() public view returns (historyValues[] memory){
        return seasonHistory;
    }

    function getSeasonHistory(uint256 _index) public view returns (uint256, address, uint256, uint256, uint256){
        require(seasonHistory.length >= 1, "At least one season has to be concluded!");

        historyValues memory temp = seasonHistory[_index];

        return (temp.season, temp.winner, temp.totalSeasonVotes, temp.voterCount, temp.winnerShare);
    }

    function updateSeasonHistory(uint256 _season, address _winner, uint256 _amount, uint256 _voter, uint256 _share) public onlyOwner (){
        
        seasonHistory.push(historyValues(_season,_winner,_amount,_voter,_share));
        collectionInformation[_winner].hasWon = true;
        season++;
    }

    function migrateOldData() public onlyOwner (){
        require(!migrated,"Migration already happened!");
        season = oldSkirmish.season();

        for (uint256 i=0; i < season; i++) 
        {
            (uint256 _season, address _winner, uint256 _amount, uint256 _voter, uint256 _share) = oldSkirmish.getSeasonHistory(i);

            seasonHistory.push(historyValues(_season,_winner,_amount,_voter,_share));
            collectionInformation[_winner].hasWon = true;
        }        
        migrated = true;
    }

    function getSeasonVoter() public view returns (activeVoter[] memory){
        require(votingActive, "Voting is not live yet!");
       
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

    function setSoulStoneAddress(address _soulStoneAddress) public onlyOwner {
        soulStoneAddress = _soulStoneAddress;
        SoulStone = ISoulStone(soulStoneAddress);
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