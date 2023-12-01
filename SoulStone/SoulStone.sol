// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SoulStone is ERC721, Ownable(msg.sender) {
    using SafeERC20 for IERC20;

    IERC20 public Soul;
    IERC20 public SoulLP;

    string public baseURI =
        "ipfs://QmY9tKo2vZgHyyzeztpGqWH6B2XjGGPfq4YhojWL6zMXfo/";

    uint256 private ID;
    uint256 public upgradeCooldownDuration = 7;
    bool initialMint = true;

    address public harvesterAddress;
    address public teamAddress;

    mapping(uint256 => Engravings) public soulStoneEngravings;
    mapping(address => uint256) public Socket;

    struct Engravings {
        uint256 level;
        uint256 baseBonus;
        uint256 cooldownTimeEnds;
        bool equippedInSocket;
        bool transferable;
        bool OG;
    }

    //initial Values
    uint256[9] public upgradeFailChance = [15, 20, 25, 30, 35, 40, 45, 50, 55]; // % fail chance
    uint256[9] public levelUpgradeCostRate = [50,80,130,225,400,650,1000,1600,2500]; // 0.005%, 0.008%, 0.013%, 0.0225%, 0.04%, 0.065%, 0.1%, 0.16%, 0.25%
    uint256[9] public levelUpgradeCostLP = [10,15,25,55,90,145,250,400,600]; // Soul LP
    uint256[10] public levelBonusHarvest = [0,5,10,15,25,35,45,60,75,90]; // % bonus
    uint256[10] public levelBonusSkirmish = [0,2,4,6,9,12,15,20,25,30]; // % bonus

    //Events
    event upgradeResults(bool upgradeSuccess,uint256 tokenIds,address indexed sender,uint256 amount);
    event mintedNext(uint256 tokenIds, address indexed sender);

    constructor() ERC721("Soul Harvester: Soul Stones", "SOULSTONE") {
        harvesterAddress = 0xBE767936403926c843fd37be1862F33c6f39e91b;
        Soul = IERC20(0x6C35Ec8df04d1417D3B02f2476c02E65b6D3B94C); //Soul Token Address
        SoulLP = IERC20(0x864b3dC46AC2B3CD444ab54680c4afCec16d6AcE); //SoulLP Token Address
        teamAddress = 0x18F15FD54537F1B4bd60C95D840Ace412e18BE38;
    }

    /**
     * @dev Try to level up a Soul Stone NFT
     */
    function tryUpgrade() public {
        require(Socket[msg.sender] > 0, "No Soulstone in the Socket!");
        uint256 _id = Socket[msg.sender];
        uint256 upgradeCosts = getEstimatedUpgradeCosts(_id);
        require(soulStoneEngravings[_id].level < 10,"This Upgrade is not necessary!");
        require(msg.sender == _ownerOf(_id),"Not the Owner of this Soul Stone!");
        require(Soul.balanceOf(msg.sender) >= upgradeCosts,"Insufficient Soul token balance");
        require(soulStoneEngravings[_id].cooldownTimeEnds <= block.timestamp,"Upgrade is still on cooldown!");

        bool upgradeSuccess;
        if (proveWorth(upgradeFailChance[soulStoneEngravings[_id].level - 1])) {
            soulStoneEngravings[_id].level++;
            //Success
            upgradeSuccess = true;
        } else {
            //Fail
            upgradeSuccess = false;
        }

        Soul.safeTransferFrom(msg.sender, address(0), upgradeCosts);
        soulStoneEngravings[_id].cooldownTimeEnds = block.timestamp + upgradeCooldownDuration * 1 days;
        emit upgradeResults(upgradeSuccess, _id, msg.sender, upgradeCosts);
    }

    /**
     * @dev Level up a Soul Stone NFT, but you have to pay the price
     */
    function guaranteedUpgrade() public {
        require(Socket[msg.sender] > 0, "No Soulstone in the Socket!");
        uint256 _id = Socket[msg.sender];
        uint256 upgradeCosts = getGuaranteedUpgradeCosts(_id);
        require(soulStoneEngravings[_id].level < 10,"Upgrade is no longer necessary!");
        require(msg.sender == _ownerOf(_id),"Not the Owner of this Soul Stone!");
        require(SoulLP.balanceOf(msg.sender) >= upgradeCosts,"Insufficient Soul token balance");

        //guaranteed level upgrade
        soulStoneEngravings[_id].level++;

        SoulLP.safeTransferFrom(msg.sender, teamAddress, upgradeCosts);

        emit upgradeResults(true, _id, msg.sender, upgradeCosts);
    }

    /**
     * @dev Gets the estimated upgrade costs for the next Upgrade
     */
    function getEstimatedUpgradeCosts(uint256 _id) public view returns (uint256)
    {
        return(Soul.balanceOf(harvesterAddress) * levelUpgradeCostRate[soulStoneEngravings[_id].level - 1]) / 1000000;
    }
    /**
     * @dev Gets the upgrade costs for the next Upgrade using LP
     */
    function getGuaranteedUpgradeCosts(uint256 _id) public view returns (uint256)
    {
        return levelUpgradeCostLP[soulStoneEngravings[_id].level - 1] * 10**18;
    }
    /**
     * @dev request if the address has a Soul Stone equipped
     */
    function hasSoulStone(address _wallet) external view returns (bool) {
        return soulStoneEngravings[Socket[_wallet]].equippedInSocket;
    }

    /**
     * @dev Gets the Harvest Bonus Value of an Soul Stone NFT
     */
    function getBonusValueHarvest(address _wallet) external view returns (uint256)
    {
        //insert calculation for the bonus value
        return soulStoneEngravings[Socket[_wallet]].baseBonus + levelBonusHarvest[soulStoneEngravings[Socket[_wallet]].level - 1];
    }
    /**
     * @dev Gets the Skirmish Bonus Value of an Soul Stone NFT
     */
    function getBonusValueSkirmish(address _wallet) external view returns (uint256)
    {
        //insert calculation for the bonus value
        return soulStoneEngravings[Socket[_wallet]].baseBonus + levelBonusSkirmish[soulStoneEngravings[Socket[_wallet]].level - 1];
    }

    /**
     * @dev RNG function for the level up
     */
    function proveWorth(uint256 _failChance) internal view returns (bool) 
    {
        if (drawNumber(100) <= _failChance) {
            return false;
        }
        return true;
    }
    /**
     * @dev Draws a "random" number
     */
    function drawNumber(uint256 range) internal view returns (uint256) {
        return
            (uint256(
                keccak256(
                    abi.encodePacked(
                        block.coinbase,
                        blockhash(block.number),
                        block.timestamp
                    )
                )
            ) % range) + 1;
    }
    /**
     * @dev returns the Total Supply
     */
    function totalSupply() public view returns (uint256) {
        return ID;
    }

    /**
     * @dev mint a Soul Stone
     */
    function mintNext(address to) external onlyOwnerOrHarvester {
        ID++;
        _safeMint(to, ID);
        soulStoneEngravings[ID].level = 1;
        Socket[to] = ID;
        soulStoneEngravings[ID].baseBonus = drawNumber(15);
        soulStoneEngravings[ID].equippedInSocket = true;
        soulStoneEngravings[ID].transferable = false;
        soulStoneEngravings[ID].OG = false;

        emit mintedNext(ID, to);
    }
    /**
     * @dev change Soul Stone Values
     */
    function changeSoulStoneEngravings(uint256 _tokenID, uint256 _level, uint256 _baseBonus,bool _transerable, bool _OG) external onlyOwnerOrHarvester {
        soulStoneEngravings[_tokenID].level = _level;
        soulStoneEngravings[_tokenID].baseBonus = _baseBonus;
        soulStoneEngravings[_tokenID].transferable = _transerable;
        soulStoneEngravings[_tokenID].OG = _OG;
    }

    /**
     * @dev equip the Soul Stone to the wallet
     */
    function equipSoulStone(uint256 _id) public {
        require(msg.sender == _ownerOf(_id),"Not the Owner of this Soul Stone!");
        require(!soulStoneEngravings[_id].equippedInSocket,"Soul Stone already equipped!");

        if (Socket[msg.sender] > 0) {soulStoneEngravings[Socket[msg.sender]].equippedInSocket = false;}

        Socket[msg.sender] = _id;
        soulStoneEngravings[_id].equippedInSocket = true;

    }

    /**
     * @dev unequip the Soul Stone from the wallet
     */
    function unequipSoulStone() public {
        uint256 _id = Socket[msg.sender];
        require(_id > 0, "There is no Soulstone equiped!");
        require(msg.sender == _ownerOf(_id),"Not the Owner of this Soul Stone!");
        require(soulStoneEngravings[_id].equippedInSocket,"Soul Stone already unequiped!");

        Socket[msg.sender] = 0;
        soulStoneEngravings[_id].equippedInSocket = false;

    }

    /**
     * @dev release the Soul Stone to sell or transfer
     */
    function release(uint256 _id) public {
        uint256 releaseCosts = (Soul.balanceOf(harvesterAddress) * levelUpgradeCostRate[3]) / 1000000;
        require(msg.sender == _ownerOf(_id),"Not the Owner of this Soul Stone!");
        require(!soulStoneEngravings[_id].transferable,"This Soul Stone is already transferable!");
        require(Soul.balanceOf(msg.sender) >= releaseCosts,"Insufficient Soul token balance");

        Soul.safeTransferFrom(msg.sender, teamAddress, releaseCosts);

        soulStoneEngravings[_id].transferable = true;

        if (_id == Socket[msg.sender]) {
            unequipSoulStone();
        }

    }

    /**
     * @dev get the costs to make the Soul Stone transferable. Necessary to sell or transfer it.
     */
    function getReleaseCosts() public view returns (uint256) {
        return(Soul.balanceOf(harvesterAddress) * levelUpgradeCostRate[3]) / 1000000;
    }

    /**
     * @dev override the transfer to make sure that the NFT can not be transferred while equiped
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        require(soulStoneEngravings[tokenId].transferable,"Token can not be transferred!");
        require(!soulStoneEngravings[tokenId].equippedInSocket,"Token is equiped in a Socket!");

        ERC721.transferFrom(from, to, tokenId);
    }



    /**
     * @dev -------- ADMIN Functions --------
     */

    modifier onlyOwnerOrHarvester() {
        address _owner = owner();
        require(
            msg.sender == _owner || msg.sender == harvesterAddress,
            "You are neither the owner nor the harvester!"
        );
        _;
    }

    /**
     * @dev mint the OG NFTs, only once!
     */
    function mintOGBatch(address[] memory inputArray) public onlyOwner {
        require(initialMint, "Initial Mint has already happened!");
        for (uint256 i = 0; i < inputArray.length; i++) {
            ID++;
            _safeMint(inputArray[i], ID);

            soulStoneEngravings[ID].level = 1;
            soulStoneEngravings[ID].baseBonus = 25;
            soulStoneEngravings[ID].equippedInSocket = false;
            soulStoneEngravings[ID].transferable = true;
            soulStoneEngravings[ID].OG = true;
        }
        initialMint = false;
    }

    /**
     * @dev change the base URI
     */
    function setURI(string memory _uri) external onlyOwner {
        baseURI = _uri;
    }

    /**
     * @dev change the address of the Harvester
     */
    function changeHarvesterAddress(address newHarvesterAddress)
        public
        onlyOwner
    {
        harvesterAddress = newHarvesterAddress;
    }

    /**
     * @dev change Soul Upgrade Cost Rate Array
     */
    function changeUpgradeCostRate(uint256[9] memory _input) public onlyOwner {
        levelUpgradeCostRate = _input;
    }

    /**
     * @dev change LP Upgrade Cost Array
     */
    function changeUpgradeCostLP(uint256[9] memory _input) public onlyOwner {
        levelUpgradeCostLP = _input;
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_ownerOf(_tokenId) != address(0), "URI query for nonexistent token");
        string memory metaOG = "Common/";
        if(soulStoneEngravings[_tokenId].OG){metaOG = "OG/";}

        string memory json = string(
            abi.encodePacked(
                'data:application/json;utf8,{"name": "Stone #',
                Strings.toString(_tokenId),
                '"',
                ',"description": "Souls will nourish this stone!", "image": "',
                abi.encodePacked(
                    baseURI,
                    metaOG,
                    Strings.toString(soulStoneEngravings[_tokenId].level),
                    ".png"
                ),
                '"',
                ',"attributes":',
                _attributes(_tokenId),
                "}"
            )
        );

        return json;
    }

    function _attributes(uint256 _tokenId)
        internal
        view
        returns (string memory)
    {
        string[5] memory _parts;

        _parts[0] = '[{ "trait_type": "Base Bonus", "value": "';
        _parts[1] = Strings.toString(soulStoneEngravings[_tokenId].baseBonus);
        _parts[2] = '" }, { "trait_type": "Level", "value": "';
        _parts[3] = Strings.toString(soulStoneEngravings[_tokenId].level);
        _parts[4] = '" }]';

        string memory _output = string(
            abi.encodePacked(
                _parts[0],
                _parts[1],
                _parts[2],
                _parts[3],
                _parts[4]
            )
        );
        return _output;
    }

}
