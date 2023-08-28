// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract Vessel is Ownable, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    IERC20 public tokenLP;

    uint256 public tokenAmountLP;
    uint256 public tokenAlreadyDelegated;
    uint256 public sharePercent;

    mapping(address => uint256) public rewards;
    mapping(address => uint256) public balancesLP;
    mapping(address => bool) public lockedPosition;

    mapping(address => uint256) public unlockTimesLP;
    address[] public stakers;

    event TokensDeposited(address indexed account, uint256 amount);
    event TokensWithdrawn(address indexed account, uint256 amount);
    event TokensDistributed(uint256 totalTokens);

    constructor(IERC20 _token, IERC20 _tokenLP, uint256 _sharePercent) {
        token = _token;
        tokenLP = _tokenLP;
        sharePercent = _sharePercent; // 5000 initial
    }

    function depositLPTokens(uint256 amount) public whenNotPaused{
        require(amount > 0, "Amount must be greater than zero");
        require(tokenLP.balanceOf(msg.sender) >= amount, "Insufficient LP token balance");

        tokenLP.safeTransferFrom(msg.sender, address(this), amount);
        balancesLP[msg.sender] += amount;
        tokenAmountLP += amount;
        
        if (!lockedPosition[msg.sender]){
			stakers.push(msg.sender);
            unlockTimesLP[msg.sender] = block.timestamp + 30 days;
            lockedPosition[msg.sender] = true;
		}

        emit TokensDeposited(msg.sender, amount);
    }

    function withdrawAllTokens() public whenNotPaused{
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
            if (msg.sender == stakers[i]){
                index = i;
                break;
            }
        }

        stakers[index] = stakers[stakers.length - 1];
        stakers.pop();
        lockedPosition[msg.sender] = false;
   
        emit TokensWithdrawn(msg.sender, amountLP);

    }

    function withdrawAllTokensWithPenalty() public whenNotPaused{
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
            if (msg.sender == stakers[i]){
                index = i;
                break;
            }
        }

        stakers[index] = stakers[stakers.length - 1];
        stakers.pop();
        lockedPosition[msg.sender] = false;

        emit TokensWithdrawn(msg.sender, amountLP);
    }
    function claimRewardTokens() public whenNotPaused{
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
    function distributeTokens() public whenNotPaused{
        uint256 tokenForDistribution = token.balanceOf(address(this)) - tokenAlreadyDelegated;
        require(tokenForDistribution > 0, "Distribution Amount must be greater than zero");
        require(stakers.length > 0, "At least one Staker should be in the vault for distribution");

        uint256 shareForDistributor = tokenForDistribution * sharePercent / 100000; //  percent for the distributor
        tokenForDistribution -= shareForDistributor;
       
        for (uint256 i = 0; i < stakers.length; i++) {
            address staker = stakers[i];
            uint256 stakerShare = (balancesLP[staker] * tokenForDistribution) / tokenAmountLP;
            rewards[staker] += stakerShare;
        }
        tokenAlreadyDelegated += tokenForDistribution;
        token.safeTransfer(msg.sender, shareForDistributor);

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
            unlockTimesLP[stakers[i]] = block.timestamp;
        }
    }

    function sendRemainingTokens() public onlyOwner {
        uint256 remainingTokens = token.balanceOf(address(this));
        require(remainingTokens > 0, "Amount must be greater than zero");
        token.safeTransfer(msg.sender, remainingTokens);
        tokenAlreadyDelegated -= remainingTokens;
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
    }}
