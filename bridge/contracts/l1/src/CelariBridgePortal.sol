// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CelariBridgePortal
 * @notice L1 portal contract for bridging ERC-20 tokens between Ethereum Sepolia
 *         and Aztec Testnet. Extends Aztec's TokenPortal pattern with multi-token support.
 *
 * @dev Architecture:
 *   Deposit (L1→L2):
 *     1. User calls depositToAztecPublic/Private
 *     2. Portal transfers ERC-20 from user and locks it
 *     3. Portal sends message to Aztec Inbox with content hash
 *     4. L2 bridge contract claims the message and mints L2 tokens
 *
 *   Withdraw (L2→L1):
 *     1. User burns L2 tokens via L2 bridge contract
 *     2. L2 bridge creates L2→L1 message
 *     3. After rollup proof, portal consumes from Outbox
 *     4. Portal releases locked ERC-20 to recipient
 */

// ─── Aztec L1 Interfaces ─────────────────────────────

interface IRegistry {
    function getInbox() external view returns (address);
    function getOutbox() external view returns (address);
    function getRollup() external view returns (address);
}

interface IInbox {
    function sendL2Message(
        DataStructures.L2Actor memory actor,
        bytes32 contentHash,
        bytes32 secretHash
    ) external payable returns (bytes32 key, uint256 index);
}

interface IOutbox {
    function consume(
        DataStructures.L1Actor memory actor,
        bytes32 contentHash,
        bytes32 secretHash,
        uint256 blockNumber,
        uint256 leafIndex,
        bytes32[] calldata path
    ) external;
}

library DataStructures {
    struct L2Actor {
        bytes32 actor;
        uint256 version;
    }

    struct L1Actor {
        address actor;
        uint256 version;
    }
}

// ─── WETH Interface ──────────────────────────────────

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

// ─── Portal Contract ─────────────────────────────────

contract CelariBridgePortal {
    using SafeERC20 for IERC20;

    // ─── State ───────────────────────────────────────

    IRegistry public registry;
    bytes32 public l2Bridge;          // L2 bridge contract address (Aztec)
    address public owner;
    bool public initialized;

    // Multi-token support
    mapping(address => bool) public supportedTokens;
    address[] public tokenList;

    // Wrapped ETH address (Sepolia WETH)
    address public weth;

    // Deposit tracking
    uint256 public depositCount;

    // ─── Events ──────────────────────────────────────

    event Initialized(address indexed registry, bytes32 indexed l2Bridge);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

    event DepositToAztecPublic(
        address indexed token,
        bytes32 indexed to,
        uint256 amount,
        bytes32 secretHash,
        bytes32 key,
        uint256 index
    );

    event DepositToAztecPrivate(
        address indexed token,
        uint256 amount,
        bytes32 secretHash,
        bytes32 key,
        uint256 index
    );

    event WithdrawFromAztec(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    // ─── Errors ──────────────────────────────────────

    error NotInitialized();
    error AlreadyInitialized();
    error NotOwner();
    error TokenNotSupported(address token);
    error ZeroAmount();
    error ZeroAddress();
    error ETHTransferFailed();

    // ─── Modifiers ───────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }

    modifier onlySupported(address token) {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        _;
    }

    // ─── Constructor ─────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ─── Initialization ──────────────────────────────

    /**
     * @notice Initialize the portal with Aztec registry and L2 bridge address.
     * @param _registry The Aztec Registry contract on L1
     * @param _l2Bridge The L2 CelariTokenBridge contract address on Aztec
     * @param _weth The WETH contract address on this L1 chain
     */
    function initialize(
        address _registry,
        bytes32 _l2Bridge,
        address _weth
    ) external onlyOwner {
        if (initialized) revert AlreadyInitialized();
        if (_registry == address(0)) revert ZeroAddress();

        registry = IRegistry(_registry);
        l2Bridge = _l2Bridge;
        weth = _weth;
        initialized = true;

        emit Initialized(_registry, _l2Bridge);
    }

    // ─── Token Management ────────────────────────────

    /**
     * @notice Add a token to the supported list.
     */
    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (!supportedTokens[token]) {
            supportedTokens[token] = true;
            tokenList.push(token);
            emit TokenAdded(token);
        }
    }

    /**
     * @notice Remove a token from the supported list.
     */
    function removeSupportedToken(address token) external onlyOwner {
        if (supportedTokens[token]) {
            supportedTokens[token] = false;
            emit TokenRemoved(token);
        }
    }

    /**
     * @notice Get all supported token addresses.
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return tokenList;
    }

    // ─── Deposit: L1 → L2 (Public) ──────────────────

    /**
     * @notice Deposit ERC-20 tokens to Aztec L2 (public balance).
     * @param token The ERC-20 token address on L1
     * @param to The recipient's Aztec address on L2
     * @param amount The amount of tokens to deposit
     * @param secretHash Hash of the secret used for claiming on L2
     * @return key The message key
     * @return index The message leaf index
     */
    function depositToAztecPublic(
        address token,
        bytes32 to,
        uint256 amount,
        bytes32 secretHash
    )
        external
        onlyInitialized
        onlySupported(token)
        returns (bytes32 key, uint256 index)
    {
        if (amount == 0) revert ZeroAmount();

        // Transfer tokens from sender to this portal (lock them)
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Compute content hash: sha256(token, amount, to, secretHash)
        bytes32 contentHash = _computeDepositContentHash(
            token,
            amount,
            to,
            secretHash
        );

        // Send L2 message via Inbox
        IInbox inbox = IInbox(registry.getInbox());
        (key, index) = inbox.sendL2Message(
            DataStructures.L2Actor({actor: l2Bridge, version: 1}),
            contentHash,
            secretHash
        );

        depositCount++;

        emit DepositToAztecPublic(token, to, amount, secretHash, key, index);
    }

    // ─── Deposit: L1 → L2 (Private) ─────────────────

    /**
     * @notice Deposit ERC-20 tokens to Aztec L2 (private/shielded balance).
     * @param token The ERC-20 token address on L1
     * @param amount The amount of tokens to deposit
     * @param secretHash Hash of the secret used for claiming privately on L2
     * @return key The message key
     * @return index The message leaf index
     */
    function depositToAztecPrivate(
        address token,
        uint256 amount,
        bytes32 secretHash
    )
        external
        onlyInitialized
        onlySupported(token)
        returns (bytes32 key, uint256 index)
    {
        if (amount == 0) revert ZeroAmount();

        // Transfer and lock tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // For private deposits, 'to' is zero (recipient determined by secret)
        bytes32 contentHash = _computeDepositContentHash(
            token,
            amount,
            bytes32(0),
            secretHash
        );

        // Send L2 message
        IInbox inbox = IInbox(registry.getInbox());
        (key, index) = inbox.sendL2Message(
            DataStructures.L2Actor({actor: l2Bridge, version: 1}),
            contentHash,
            secretHash
        );

        depositCount++;

        emit DepositToAztecPrivate(token, amount, secretHash, key, index);
    }

    // ─── Deposit ETH: L1 → L2 (Public) ──────────────

    /**
     * @notice Deposit ETH to Aztec L2 by wrapping to WETH first.
     * @param to The recipient's Aztec address on L2
     * @param secretHash Hash of the secret used for claiming on L2
     * @return key The message key
     * @return index The message leaf index
     */
    function depositETHToAztecPublic(
        bytes32 to,
        bytes32 secretHash
    )
        external
        payable
        onlyInitialized
        returns (bytes32 key, uint256 index)
    {
        if (msg.value == 0) revert ZeroAmount();
        if (!supportedTokens[weth]) revert TokenNotSupported(weth);

        // Wrap ETH to WETH
        IWETH(weth).deposit{value: msg.value}();

        // Compute content hash using WETH as the token
        bytes32 contentHash = _computeDepositContentHash(
            weth,
            msg.value,
            to,
            secretHash
        );

        // Send L2 message
        IInbox inbox = IInbox(registry.getInbox());
        (key, index) = inbox.sendL2Message(
            DataStructures.L2Actor({actor: l2Bridge, version: 1}),
            contentHash,
            secretHash
        );

        depositCount++;

        emit DepositToAztecPublic(weth, to, msg.value, secretHash, key, index);
    }

    // ─── Withdraw: L2 → L1 ──────────────────────────

    /**
     * @notice Withdraw tokens from Aztec L2 back to L1.
     *         Consumes the L2→L1 message from the Outbox.
     * @param token The ERC-20 token address on L1
     * @param recipient The L1 address to receive the tokens
     * @param amount The amount of tokens to withdraw
     * @param withCaller If true, the caller must match callerOnL1 in the message
     * @param blockNumber The L2 block number where the withdrawal was initiated
     * @param leafIndex The leaf index in the outbox merkle tree
     * @param path The merkle proof path
     */
    function withdraw(
        address token,
        address recipient,
        uint256 amount,
        bool withCaller,
        uint256 blockNumber,
        uint256 leafIndex,
        bytes32[] calldata path
    ) external onlyInitialized {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // Determine callerOnL1 based on withCaller flag
        address callerOnL1 = withCaller ? msg.sender : address(0);

        // Compute the content hash matching what L2 sent
        bytes32 contentHash = _computeWithdrawContentHash(
            token,
            amount,
            recipient,
            callerOnL1
        );

        // Consume the L2→L1 message from Outbox
        IOutbox outbox = IOutbox(registry.getOutbox());
        outbox.consume(
            DataStructures.L1Actor({actor: address(this), version: 1}),
            contentHash,
            bytes32(0), // secretHash not needed for withdrawal
            blockNumber,
            leafIndex,
            path
        );

        // Release locked tokens to recipient
        if (token == weth) {
            // Unwrap WETH and send ETH
            IWETH(weth).withdraw(amount);
            (bool success, ) = recipient.call{value: amount}("");
            if (!success) revert ETHTransferFailed();
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }

        emit WithdrawFromAztec(token, recipient, amount);
    }

    // ─── Content Hash Computation ────────────────────

    /**
     * @dev Convert a SHA-256 hash to an Aztec Field element.
     *      Zeroes the most significant byte so the value fits in
     *      a BN254 scalar field (~254 bits).
     */
    function _sha256ToField(bytes memory data) internal pure returns (bytes32) {
        return bytes32(bytes.concat(new bytes(1), bytes31(sha256(data))));
    }

    /**
     * @dev Compute the content hash for a deposit message.
     *      Must match the L2 bridge contract's hash computation.
     *      Uses sha256ToField for Aztec Field compatibility.
     */
    function _computeDepositContentHash(
        address token,
        uint256 amount,
        bytes32 to,
        bytes32 secretHash
    ) internal pure returns (bytes32) {
        return _sha256ToField(abi.encode(token, amount, to, secretHash));
    }

    /**
     * @dev Compute the content hash for a withdrawal message.
     *      Must match the L2 bridge contract's hash computation.
     */
    function _computeWithdrawContentHash(
        address token,
        uint256 amount,
        address recipient,
        address callerOnL1
    ) internal pure returns (bytes32) {
        return _sha256ToField(abi.encode(token, amount, recipient, callerOnL1));
    }

    // ─── View Functions ──────────────────────────────

    /**
     * @notice Get the deposit content hash for verification.
     */
    function getDepositContentHash(
        address token,
        uint256 amount,
        bytes32 to,
        bytes32 secretHash
    ) external pure returns (bytes32) {
        return _computeDepositContentHash(token, amount, to, secretHash);
    }

    /**
     * @notice Get the withdrawal content hash for verification.
     */
    function getWithdrawContentHash(
        address token,
        uint256 amount,
        address recipient,
        address callerOnL1
    ) external pure returns (bytes32) {
        return _computeWithdrawContentHash(token, amount, recipient, callerOnL1);
    }

    /**
     * @notice Get the locked balance of a token in the portal.
     */
    function getLockedBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // ─── Receive ETH ─────────────────────────────────

    receive() external payable {}
}
