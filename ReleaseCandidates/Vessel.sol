// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Vessel is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public token;
    IERC20 public tokenLP;

    uint256 public tokenAmountLP;
    uint256 public tokenAlreadyDelegated;
    uint256 public sharePercent;
    uint256 public numberOfStaker;
    uint256 public numberOfBountyHunter;

    mapping(address => uint256) public rewards;
    mapping(address => uint256) public balancesLP;
    mapping(address => bool) public lockedPosition;

    mapping(address => uint256) public unlockTimesLP;

    struct Staker {
        address stakerAddress;
        uint256 actualStakedAmount;
    }

    Staker[] public stakers;

    struct BountyHunter {
        address bountyHunterAddress;
        uint256 bounty;
    }

    BountyHunter[] public bountyHunters;

    event TokensDeposited(address indexed account, uint256 amount);
    event TokensWithdrawn(address indexed account, uint256 amount);
    event TokensDistributed(uint256 totalTokens);

    event StakerAdded(address indexed userAddress, uint256 actualStakedAmount);
    event StakerUpdated(address indexed userAddress,  uint256 oldActualStakedAmount, uint256 newActualStakedAmount);
    event BountyHunterAdded(address indexed userAddress, uint256 actualStakedAmount);
    event BountyHunterUpdated(address indexed userAddress,  uint256 oldActualStakedAmount, uint256 newActualStakedAmount);


    constructor(IERC20 _token, IERC20 _tokenLP, uint256 _sharePercent) {
        token = _token;
        tokenLP = _tokenLP;
        sharePercent = _sharePercent; // 5000 initial
    }

    function depositLPTokens(uint256 amount) public nonReentrant whenNotPaused{
        require(amount > 0, "Amount must be greater than zero");
        require(tokenLP.balanceOf(msg.sender) >= amount, "Insufficient LP token balance");

        tokenLP.safeTransferFrom(msg.sender, address(this), amount);
        balancesLP[msg.sender] += amount;
        tokenAmountLP += amount;
		updateStakerValues(msg.sender, balancesLP[msg.sender]);
        
        if (!lockedPosition[msg.sender]){
            unlockTimesLP[msg.sender] = block.timestamp + 30 days;
            lockedPosition[msg.sender] = true;
		}

        emit TokensDeposited(msg.sender, amount);
    }

    function withdrawAllTokens() public nonReentrant whenNotPaused{
        uint256 amountLP = balancesLP[msg.sender];
        uint256 reward = rewards[msg.sender];

        require(amountLP > 0, "No tokens to withdraw");
        require(block.timestamp >= unlockTimesLP[msg.sender], "Tokens are still locked");

       
        tokenLP.safeTransfer(msg.sender, amountLP);
        token.safeTransfer(msg.sender,reward);
   
        tokenAmountLP -= amountLP;
        tokenAlreadyDelegated -= reward;

        balancesLP[msg.sender] = 0;
        rewards[msg.sender] = 0;  


        uint256 index;

        for(uint256 i = 0; i < stakers.length; i++){
            if (msg.sender == stakers[i].stakerAddress){
                index = i;
                break;
            }
        }

        stakers[index] = stakers[stakers.length - 1];
        stakers.pop();
        lockedPosition[msg.sender] = false;
        numberOfStaker--;

        emit TokensWithdrawn(msg.sender, amountLP);

    }

    function withdrawAllTokensWithPenalty() public nonReentrant whenNotPaused{
        uint256 reward = rewards[msg.sender];
        uint256 amountLP = balancesLP[msg.sender];
        uint256 penalty = reward * 50 / 100;        
        
        require(amountLP > 0, "No tokens to withdraw");
        require(block.timestamp < unlockTimesLP[msg.sender], "Tokens are already unlocked");
        

        tokenLP.safeTransfer(msg.sender, amountLP);
        token.safeTransfer(msg.sender,(reward - penalty));
   
        tokenAmountLP -= amountLP;
        tokenAlreadyDelegated -= reward;

        balancesLP[msg.sender] = 0;
        rewards[msg.sender] = 0;  
        unlockTimesLP[msg.sender] = block.timestamp;

        uint256 index;

        for(uint256 i = 0; i < stakers.length; i++){
            if (msg.sender == stakers[i].stakerAddress){
                index = i;
                break;
            }
        }

        stakers[index] = stakers[stakers.length - 1];
        stakers.pop();
        lockedPosition[msg.sender] = false;
        numberOfStaker--;
        emit TokensWithdrawn(msg.sender, amountLP);
    }
    function claimRewardTokens() public nonReentrant whenNotPaused{
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No tokens to withdraw");
        require(block.timestamp >= unlockTimesLP[msg.sender], "Tokens are still locked");
        tokenAlreadyDelegated -= reward;
        token.safeTransfer(msg.sender,reward);
   
        rewards[msg.sender] = 0;        
  
        emit TokensWithdrawn(msg.sender, reward);

    } 
    //distribute the token the contract is holding to the stakers
    //distributor gets the bounty for paying the gas
    function distributeTokens() public nonReentrant whenNotPaused{
        uint256 tokenForDistribution = token.balanceOf(address(this)) - tokenAlreadyDelegated;
        require(tokenForDistribution > 0, "Distribution Amount must be greater than zero");
        require(stakers.length > 0, "At least one Staker should be in the vault for distribution");

        uint256 shareForDistributor = tokenForDistribution * sharePercent / 100000; //  percent for the distributor
        tokenForDistribution -= shareForDistributor;
       
        for (uint256 i = 0; i < stakers.length; i++) {
            address staker = stakers[i].stakerAddress;
            uint256 stakerShare = (balancesLP[staker] * tokenForDistribution) / tokenAmountLP;
            rewards[staker] += stakerShare;
        }
        tokenAlreadyDelegated += tokenForDistribution;
        token.safeTransfer(msg.sender, shareForDistributor);
        
        updateBountyHunterValues(msg.sender, shareForDistributor);

        emit TokensDistributed(tokenForDistribution);
    }
    function getDistributionReward() public view returns (uint256 _distributionReward){
        uint256 shareForDistributor = (token.balanceOf(address(this)) - tokenAlreadyDelegated) * sharePercent / 100000; // X percent for the distributor
        return shareForDistributor;
    }
    function getShareForWallet(address _wallet) public view returns (uint256 _share){
        uint256 share = 0;

        if (tokenAmountLP > 0){
            share = balancesLP[_wallet] * 100000 / tokenAmountLP;
        }
        
        return share;
    }

    function unlockAllDeposits() public onlyOwner {

        for(uint256 i = 0; i < stakers.length; i++){
            unlockTimesLP[stakers[i].stakerAddress] = block.timestamp;
        }
    }

    function sendRemainingTokens() public onlyOwner {
        uint256 remainingTokens = token.balanceOf(address(this));
        require(remainingTokens > 0, "Amount must be greater than zero");
        token.safeTransfer(msg.sender, remainingTokens);
        tokenAlreadyDelegated -= remainingTokens;

        for (uint256 i = 0; i < stakers.length; i++) {
            address staker = stakers[i].stakerAddress;
            rewards[staker] = 0;
        }
    }

    function setTokenAddress(address _tokenAddress) public onlyOwner {
        token = IERC20(_tokenAddress);
        tokenAlreadyDelegated = 0;
    }

    function setLPTokenAddress(address _tokenAddress) public onlyOwner {
        tokenLP = IERC20(_tokenAddress);
    }

    function setSharePercent(uint256 _sharePercent) public onlyOwner {
        require(_sharePercent <= 100000 && _sharePercent >= 0,"Share exeeds the bounds!");

        sharePercent = _sharePercent;
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
    
    function updateStakerValues(address _userAddress, uint256 _actualStakedAmount) internal {
        uint256 index = findStakerIndex(_userAddress);

        if(index != type(uint256).max){
            uint256 oldActualStakedAmount = stakers[index].actualStakedAmount;
            stakers[index].actualStakedAmount = _actualStakedAmount;
    
            emit StakerUpdated(_userAddress, oldActualStakedAmount, _actualStakedAmount);
        }
        else{
            stakers.push(Staker(_userAddress, _actualStakedAmount));
            numberOfStaker++;
            emit StakerAdded(_userAddress, _actualStakedAmount);
        }
        

    }

    function getTopStakerByActualStakedAmount(uint256 numberOfTopStaker) public view returns (Staker[] memory) {
        require(numberOfTopStaker <= numberOfStaker, "Not enough users in the leaderboard");
        Staker[] memory returnStaker = new Staker[](numberOfTopStaker);

        // Sort users by score
        Staker[] memory sortedStaker = sortStakerByActualStakedAmount();

        for (uint256 i = 0; i < numberOfTopStaker; i++) {
            Staker memory staker = sortedStaker[i];
            returnStaker[i].stakerAddress = staker.stakerAddress;
            returnStaker[i].actualStakedAmount = staker.actualStakedAmount;
        }

        return (returnStaker);
    }

    function sortStakerByActualStakedAmount() internal view returns (Staker[] memory) {
        Staker[] memory sortedStaker = stakers;

        for (uint256 i = 0; i < sortedStaker.length; i++) {
            for (uint256 j = i + 1; j < sortedStaker.length; j++) {
                if (sortedStaker[i].actualStakedAmount < sortedStaker[j].actualStakedAmount) {
                    Staker memory temp = sortedStaker[i];
                    sortedStaker[i] = sortedStaker[j];
                    sortedStaker[j] = temp;
                }
            }
        }

        return sortedStaker;
    }

    function findStakerIndex(address _userAddress) internal view returns (uint256) {
        for (uint256 i = 0; i < stakers.length; i++) {
            if (stakers[i].stakerAddress == _userAddress) {
                return i;
            }
        }
        return type(uint256).max; // Not found
    }

    function updateBountyHunterValues(address _userAddress, uint256 _incBounty) internal {
        uint256 index = findBountyHunterIndex(_userAddress);

        if(index != type(uint256).max){
            uint256 oldBounty = bountyHunters[index].bounty;
            bountyHunters[index].bounty += _incBounty;
    
            emit BountyHunterUpdated(_userAddress, oldBounty, _incBounty);
        }
        else{
            bountyHunters.push(BountyHunter(_userAddress, _incBounty));
            numberOfBountyHunter++;
            emit BountyHunterAdded(_userAddress, _incBounty);
        }
        

    }

    function getTopBountyHunterByBounty(uint256 numberOfTopBountyHunter) public view returns (BountyHunter[] memory) {
        require(numberOfTopBountyHunter <= numberOfBountyHunter, "Not enough users in the leaderboard");
        BountyHunter[] memory returnBountyHunter = new BountyHunter[](numberOfTopBountyHunter);

        // Sort users by score
        BountyHunter[] memory sortedBountyHunter = sortBountyHunterByBounty();

        for (uint256 i = 0; i < numberOfTopBountyHunter; i++) {
            BountyHunter memory bountyHunter = sortedBountyHunter[i];
            returnBountyHunter[i].bountyHunterAddress = bountyHunter.bountyHunterAddress;
            returnBountyHunter[i].bounty = bountyHunter.bounty;
        }

        return (returnBountyHunter);
    }

    function sortBountyHunterByBounty() internal view returns (BountyHunter[] memory) {
        BountyHunter[] memory sortedBountyHunter = bountyHunters;

        for (uint256 i = 0; i < sortedBountyHunter.length; i++) {
            for (uint256 j = i + 1; j < sortedBountyHunter.length; j++) {
                if (sortedBountyHunter[i].bounty < sortedBountyHunter[j].bounty) {
                    BountyHunter memory temp = sortedBountyHunter[i];
                    sortedBountyHunter[i] = sortedBountyHunter[j];
                    sortedBountyHunter[j] = temp;
                }
            }
        }

        return sortedBountyHunter;
    }

    function findBountyHunterIndex(address _userAddress) internal view returns (uint256) {
        for (uint256 i = 0; i < bountyHunters.length; i++) {
            if (bountyHunters[i].bountyHunterAddress == _userAddress) {
                return i;
            }
        }
        return type(uint256).max; // Not found
    }
    
    }
