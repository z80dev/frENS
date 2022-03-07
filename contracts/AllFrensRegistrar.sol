//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;


import "./IENS.sol";
import "./IResolver.sol";
import "./IERC721.sol";
import "./ERC721.sol";

/**
 * A registrar that allocates subdomains reserved subdomains to authorized NFT holders
 */
contract AllFrensRegistrar is ERC721 {
    /* STORAGE */
    address registrarController; // can set fee
    address feeRecipient; // receives platform fee
    address ens = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address publicResolver = 0x4B1488B7a6B320d2D721406204aBc3eeAa9AD329;
    uint256 FEE = 0.05 ether;

    /* Access Control */
    // support multiple subdomains for a collection
    mapping(bytes32 => bool) public subdomainEnabledForCollection; // key is hash(subdomain, collection)
    mapping(bytes32 => bytes32) public subdomainForNFT; // key is hash(subdomain, collection, tokenID)
    mapping(address => mapping(uint256 => bytes32)) public nodehashForNFT;

    /* Track Subdomain Information */
    mapping(uint256 => bytes32) labelForId;
    mapping(uint256 => bytes32) rootNodeForId;
    mapping(bytes32 => address) originalRegistrant; // only let one address register a subdomain, prevent impersonation

    bool public enabled = false;

    modifier hodler(address collection, uint256 id) {
        require(IERC721(collection).ownerOf(id) == msg.sender, "Not NFT Owner");
        _;
    }

    modifier controllerOnly() {
        require(msg.sender == registrarController);
        _;
    }

    function setController(address newController) public controllerOnly() {
        registrarController = newController;
    }

    constructor() ERC721("frENS", "frENS") {
        registrarController = msg.sender;
    }

    function setSubdomainCollectionAuth(bytes32 rootnode, address collection, bool auth) external {
        require(IENS(ens).owner(rootnode) == msg.sender, "Not domain owner");
        bytes32 key = keccak256(abi.encode(rootnode, collection));
        subdomainEnabledForCollection[key] = auth;
    }

    function isSubdomainEnabledForCollection(bytes32 rootnode, address collection) internal view returns (bool) {
        bytes32 key = keccak256(abi.encode(rootnode, collection));
        return subdomainEnabledForCollection[key];
    }

    function transferFrom(address from, address to, uint256 id) public override {
        super.transferFrom(from, to, id);
        // take temporary ownership in order to set addr w/ resolver
        IENS(ens).setSubnodeOwner(rootNodeForId[id], labelForId[id], address(this));
        IResolver(publicResolver).setAddr(bytes32(id), to);
        IENS(ens).setSubnodeOwner(rootNodeForId[id], labelForId[id], to);
    }

    function safeTransferFrom(address from, address to, uint256 id) public override {
        super.safeTransferFrom(from, to, id);
        // take temporary ownership in order to set resolver addr
        IENS(ens).setSubnodeOwner(rootNodeForId[id], labelForId[id], address(this));
        IResolver(publicResolver).setAddr(bytes32(id), to);
        IENS(ens).setSubnodeOwner(rootNodeForId[id], labelForId[id], to);
    }

    function setEnabled(bool _enabled) controllerOnly external {
        enabled = _enabled;
    }

    function setFee(uint256 _fee) controllerOnly external {
        FEE = _fee;
    }

    function chargeFee() internal {
        require(msg.value >= FEE, "FEE NOT PAID");
        if (msg.value > FEE) {
            payable(msg.sender).transfer(msg.value - FEE);
        }
        payable(feeRecipient).transfer(FEE);
    }

    /**
     * Register a name, or reclaim an existing registration.
     */
    function register(bytes32 label, bytes32 rootNode, address collection, uint256 id) payable public hodler(collection, id) {
        require(enabled, "DISABLED");

        // check if NFT has a subdomain registered already
        bytes32 subdomainKey = keccak256(abi.encode(rootNode, collection, id));
        bytes32 currentNode = subdomainForNFT[subdomainKey];
        if (currentNode != bytes32(0)) {
            // delete current record if it exists
            IENS(ens).setSubnodeRecord(rootNodeForId[uint256(currentNode)], labelForId[uint256(currentNode)], address(0), address(0), 0);
            // burn existing NFT
            _burn(uint256(currentNode));
        }

        require(isSubdomainEnabledForCollection(rootNode, collection), "Subdomain AUTH");

        // calculate nodehash
        bytes32 nodehash = keccak256(abi.encodePacked(rootNode, label));

        // check name is available
        require(!IENS(ens).recordExists(nodehash), "TAKEN");

        // check its never been registered, or been registered by this address
        require(originalRegistrant[nodehash] == address(0) || originalRegistrant[nodehash] == msg.sender);

        chargeFee();

        // store state (maybe should be a struct?)
        subdomainForNFT[subdomainKey] = nodehash;
        labelForId[uint256(nodehash)] = label;
        rootNodeForId[uint256(nodehash)] = rootNode;

        // issue subdomain
        IENS(ens).setSubnodeRecord(rootNode, label, address(this), publicResolver, 5);
        IResolver(publicResolver).setAddr(nodehash, msg.sender);
        IENS(ens).setSubnodeOwner(rootNode, label, msg.sender);
        _mint(msg.sender, uint256(nodehash));
    }

}
