// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/CelariBridgePortal.sol";

// ─── Mock Contracts ──────────────────────────────────

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract MockInbox {
    uint256 public messageCount;

    function sendL2Message(
        DataStructures.L2Actor memory,
        bytes32,
        bytes32
    ) external payable returns (bytes32 key, uint256 index) {
        messageCount++;
        key = keccak256(abi.encodePacked(messageCount));
        index = messageCount - 1;
    }
}

contract MockOutbox {
    bool public shouldFail;

    function setShouldFail(bool _fail) external {
        shouldFail = _fail;
    }

    function consume(
        DataStructures.L1Actor memory,
        bytes32,
        bytes32,
        uint256,
        uint256,
        bytes32[] calldata
    ) external view {
        require(!shouldFail, "MockOutbox: consume failed");
    }
}

contract MockRegistry is IRegistry {
    address public inbox;
    address public outbox;
    address public rollup;

    constructor(address _inbox, address _outbox) {
        inbox = _inbox;
        outbox = _outbox;
    }

    function getInbox() external view returns (address) { return inbox; }
    function getOutbox() external view returns (address) { return outbox; }
    function getRollup() external view returns (address) { return rollup; }
}

contract MockWETH is MockERC20, IWETH {
    constructor() MockERC20("Wrapped ETH", "WETH") {}

    function deposit() external payable override {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
    }

    function withdraw(uint256 amount) external override {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "WETH: ETH transfer failed");
    }

    receive() external payable {}
}

// ─── Tests ───────────────────────────────────────────

contract CelariBridgePortalTest is Test {
    CelariBridgePortal portal;
    MockERC20 testToken;
    MockWETH weth;
    MockInbox inbox;
    MockOutbox outbox;
    MockRegistry registry;

    address owner = address(this);
    address user = address(0xBEEF);
    bytes32 l2Bridge = bytes32(uint256(0xDEAD));
    bytes32 recipientAztec = bytes32(uint256(0xCAFE));
    bytes32 secretHash = bytes32(uint256(0x1234));

    function setUp() public {
        // Deploy mocks
        inbox = new MockInbox();
        outbox = new MockOutbox();
        registry = new MockRegistry(address(inbox), address(outbox));
        weth = new MockWETH();
        testToken = new MockERC20("Test Token", "TST");

        // Deploy portal
        portal = new CelariBridgePortal();

        // Initialize
        portal.initialize(address(registry), l2Bridge, address(weth));

        // Add supported tokens
        portal.addSupportedToken(address(testToken));
        portal.addSupportedToken(address(weth));

        // Mint tokens for user
        testToken.mint(user, 1000 ether);
        vm.deal(user, 100 ether);
    }

    // ─── Initialization Tests ────────────────────────

    function test_initialization() public view {
        assertTrue(portal.initialized());
        assertEq(address(portal.registry()), address(registry));
        assertEq(portal.l2Bridge(), l2Bridge);
        assertEq(portal.weth(), address(weth));
        assertEq(portal.owner(), owner);
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert(CelariBridgePortal.AlreadyInitialized.selector);
        portal.initialize(address(registry), l2Bridge, address(weth));
    }

    function test_onlyOwnerCanInitialize() public {
        CelariBridgePortal newPortal = new CelariBridgePortal();
        vm.prank(user);
        vm.expectRevert(CelariBridgePortal.NotOwner.selector);
        newPortal.initialize(address(registry), l2Bridge, address(weth));
    }

    // ─── Token Management Tests ──────────────────────

    function test_addSupportedToken() public {
        MockERC20 newToken = new MockERC20("New", "NEW");
        portal.addSupportedToken(address(newToken));
        assertTrue(portal.supportedTokens(address(newToken)));
    }

    function test_removeSupportedToken() public {
        portal.removeSupportedToken(address(testToken));
        assertFalse(portal.supportedTokens(address(testToken)));
    }

    function test_getSupportedTokens() public view {
        address[] memory tokens = portal.getSupportedTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(testToken));
        assertEq(tokens[1], address(weth));
    }

    // ─── Deposit Public Tests ────────────────────────

    function test_depositToAztecPublic() public {
        uint256 amount = 100 ether;

        vm.startPrank(user);
        testToken.approve(address(portal), amount);

        (bytes32 key, uint256 index) = portal.depositToAztecPublic(
            address(testToken),
            recipientAztec,
            amount,
            secretHash
        );

        vm.stopPrank();

        // Verify token transfer
        assertEq(testToken.balanceOf(address(portal)), amount);
        assertEq(testToken.balanceOf(user), 900 ether);

        // Verify message was sent
        assertTrue(key != bytes32(0));
        assertEq(index, 0);
        assertEq(portal.depositCount(), 1);
    }

    function test_depositZeroAmountReverts() public {
        vm.prank(user);
        vm.expectRevert(CelariBridgePortal.ZeroAmount.selector);
        portal.depositToAztecPublic(
            address(testToken),
            recipientAztec,
            0,
            secretHash
        );
    }

    function test_depositUnsupportedTokenReverts() public {
        MockERC20 unsupported = new MockERC20("Bad", "BAD");
        unsupported.mint(user, 100 ether);

        vm.startPrank(user);
        unsupported.approve(address(portal), 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                CelariBridgePortal.TokenNotSupported.selector,
                address(unsupported)
            )
        );
        portal.depositToAztecPublic(
            address(unsupported),
            recipientAztec,
            100 ether,
            secretHash
        );
        vm.stopPrank();
    }

    // ─── Deposit Private Tests ───────────────────────

    function test_depositToAztecPrivate() public {
        uint256 amount = 50 ether;

        vm.startPrank(user);
        testToken.approve(address(portal), amount);

        (bytes32 key, uint256 index) = portal.depositToAztecPrivate(
            address(testToken),
            amount,
            secretHash
        );

        vm.stopPrank();

        assertEq(testToken.balanceOf(address(portal)), amount);
        assertTrue(key != bytes32(0));
        assertEq(index, 0);
    }

    // ─── Deposit ETH Tests ───────────────────────────

    function test_depositETHToAztecPublic() public {
        uint256 amount = 1 ether;

        vm.prank(user);
        (bytes32 key, uint256 index) = portal.depositETHToAztecPublic{value: amount}(
            recipientAztec,
            secretHash
        );

        // WETH should be held by portal
        assertEq(weth.balanceOf(address(portal)), amount);
        assertTrue(key != bytes32(0));
        assertEq(index, 0);
    }

    function test_depositETHZeroReverts() public {
        vm.prank(user);
        vm.expectRevert(CelariBridgePortal.ZeroAmount.selector);
        portal.depositETHToAztecPublic{value: 0}(
            recipientAztec,
            secretHash
        );
    }

    // ─── Withdraw Tests ──────────────────────────────

    function test_withdraw() public {
        // First deposit tokens to the portal
        uint256 amount = 100 ether;
        vm.startPrank(user);
        testToken.approve(address(portal), amount);
        portal.depositToAztecPublic(
            address(testToken),
            recipientAztec,
            amount,
            secretHash
        );
        vm.stopPrank();

        // Now withdraw
        bytes32[] memory path = new bytes32[](0);
        portal.withdraw(
            address(testToken),
            user,
            amount,
            false, // withCaller
            1,     // blockNumber
            0,     // leafIndex
            path
        );

        assertEq(testToken.balanceOf(user), 1000 ether); // back to original
        assertEq(testToken.balanceOf(address(portal)), 0);
    }

    function test_withdrawZeroAmountReverts() public {
        bytes32[] memory path = new bytes32[](0);
        vm.expectRevert(CelariBridgePortal.ZeroAmount.selector);
        portal.withdraw(
            address(testToken),
            user,
            0,
            false,
            1,
            0,
            path
        );
    }

    // ─── Content Hash Tests ──────────────────────────

    function test_depositContentHash() public view {
        bytes32 hash = portal.getDepositContentHash(
            address(testToken),
            100 ether,
            recipientAztec,
            secretHash
        );
        // Hash should be deterministic and use sha256ToField (MSB zeroed)
        bytes32 rawHash = sha256(
            abi.encode(address(testToken), uint256(100 ether), recipientAztec, secretHash)
        );
        bytes32 expected = bytes32(bytes.concat(new bytes(1), bytes31(rawHash)));
        assertEq(hash, expected);
        // Verify MSB is zeroed
        assertEq(uint8(hash[0]), 0);
    }

    function test_withdrawContentHash() public view {
        bytes32 hash = portal.getWithdrawContentHash(
            address(testToken),
            100 ether,
            user,
            address(0)
        );
        bytes32 rawHash = sha256(
            abi.encode(address(testToken), uint256(100 ether), user, address(0))
        );
        bytes32 expected = bytes32(bytes.concat(new bytes(1), bytes31(rawHash)));
        assertEq(hash, expected);
    }

    // ─── Multiple Deposits Test ──────────────────────

    function test_multipleDeposits() public {
        vm.startPrank(user);
        testToken.approve(address(portal), 300 ether);

        portal.depositToAztecPublic(address(testToken), recipientAztec, 100 ether, secretHash);
        portal.depositToAztecPublic(address(testToken), recipientAztec, 100 ether, secretHash);
        portal.depositToAztecPublic(address(testToken), recipientAztec, 100 ether, secretHash);

        vm.stopPrank();

        assertEq(portal.depositCount(), 3);
        assertEq(testToken.balanceOf(address(portal)), 300 ether);
    }

    // ─── Not Initialized Tests ───────────────────────

    function test_depositBeforeInitReverts() public {
        CelariBridgePortal newPortal = new CelariBridgePortal();
        vm.expectRevert(CelariBridgePortal.NotInitialized.selector);
        newPortal.depositToAztecPublic(
            address(testToken),
            recipientAztec,
            100 ether,
            secretHash
        );
    }
}
