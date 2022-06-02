from vyper.interfaces import ERC721

interface IENS:
    def owner(node: bytes32) -> address: view
    def recordExists(node: bytes32) -> bool: view
    def setSubnodeOwner(node: bytes32, label: bytes32, owner: address) -> bytes32: nonpayable
    def setSubnodeRecord(node: bytes32, label: bytes32, owner: address, resolver: address, ttl: uint64): nonpayable

interface IResolver:
    def setAddr(nodehash: bytes32, addr: address): nonpayable

# internal state
enabled: public(bool)
controller: public(address)
feeRecipient: public(address)
fee: public(uint256)

# access control
subdomainEnabledForCollection: public(HashMap[bytes32, HashMap[address, bool]])
subdomainForNFT: public(HashMap[bytes32, HashMap[address, HashMap[uint256, bytes32]]])

# ens addresses
ENS: immutable(IENS)
PUBLIC_RESOLVER: immutable(address)

# track subdomain information
labelForNode: HashMap[bytes32, bytes32]
root: HashMap[bytes32, bytes32]
originalRegistrant: HashMap[bytes32, address]

@external
def __init__(resolver: address):
    PUBLIC_RESOLVER = resolver
    self.controller = msg.sender
    ENS = IENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e)

@external
def setController(newController: address):
    assert msg.sender == self.controller, "unauth"
    self.controller = newController

@external
def setEnabled(enabled: bool):
    assert msg.sender == self.controller, "unauth"
    self.enabled = enabled

@external
def setFee(fee: uint256):
    assert msg.sender == self.controller, "unauth"
    self.fee = fee

@external
def setSubdomainCollectionAuth(rootNode: bytes32, collection: address, auth: bool):
    assert msg.sender == ENS.owner(rootNode), "not domain owner"
    self.subdomainEnabledForCollection[rootNode][collection] = auth

@external
def register(label: bytes32, rootNode: bytes32, collection: address, id: uint256):
    assert self.enabled, "disabled"
    assert self.subdomainEnabledForCollection[rootNode][collection], "subdomain auth"
    assert ERC721(collection).ownerOf(id) == msg.sender, "not hodler"

    currentNode: bytes32 = self.subdomainForNFT[rootNode][collection][id]
    if currentNode != EMPTY_BYTES32:
       ENS.setSubnodeRecord(self.root[currentNode], self.labelForNode[currentNode], ZERO_ADDRESS, ZERO_ADDRESS, 0)

    nodehash: bytes32 = keccak256(concat(rootNode, label))

    assert not ENS.recordExists(nodehash), "taken"

    originalRegistrant: address = self.originalRegistrant[nodehash]

    if originalRegistrant != ZERO_ADDRESS:
        assert originalRegistrant == msg.sender, "reserved"

    self.subdomainForNFT[rootNode][collection][id] = nodehash
    self.originalRegistrant[nodehash] = msg.sender
    self.labelForNode[nodehash] = label
    self.root[nodehash] = rootNode

    # ENS.setSubnodeRecord(rootNode, label, self, convert(PUBLIC_RESOLVER, address), 5)
    ENS.setSubnodeRecord(rootNode, label, self, PUBLIC_RESOLVER, 5)
    IResolver(PUBLIC_RESOLVER).setAddr(nodehash, msg.sender)
    ENS.setSubnodeOwner(rootNode, label, msg.sender)
