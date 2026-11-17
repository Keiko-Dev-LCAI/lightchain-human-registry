// SPDX-License-Identifier: MIT
// Copyright (c) 2026 KeikoDev
pragma solidity ^0.8.24;

/*
 * Lightchain Human Registry: proof of concept
 * -------------------------------------------
 * One "verified human" badge per passport/ID document, using ZKPassport
 * zero-knowledge proofs. The registry stores only (nullifier -> wallet).
 *
 * STATUS: NOT COMPILED, NOT TESTED, NOT AUDITED, NOT DEPLOYED.
 *
 * This file does NOT include any ZKPassport code. It talks to a deployed
 * ZKPassport RootVerifier by address through the minimal interface below.
 *
 * ============================== UNVERIFIED ==============================
 * The structs and interfaces below are written from ZKPassport's PUBLIC
 * DOCS (docs/getting-started/onchain.md) and the registry-contracts source
 * we read on 2026-11-17. They were NOT checked against a specific deployed
 * version. Before any deployment:
 *   1. Compare every struct field (order and types) with the exact
 *      ZKPassport release you deploy (lib/Types.sol in
 *      zkpassport-packages/packages/registry-contracts).
 *   2. Confirm the verify() return tuple and the helper function names.
 *   3. Confirm the public-input layout (nullifier type at length-4).
 * See ../research-zkpassport.md, sections 1 and 3.
 * ========================================================================
 */

// ---------------------------------------------------------------------
// ZKPassport types (UNVERIFIED mirror of their documented ABI)
// ---------------------------------------------------------------------

struct ProofVerificationData {
    bytes32 vkeyHash;
    bytes proof;
    bytes32[] publicInputs;
}

struct ServiceConfig {
    uint256 validityPeriodInSeconds;
    string domain;
    string scope;
    bool devMode;
}

struct ProofVerificationParams {
    bytes32 version;
    ProofVerificationData proofVerificationData;
    bytes committedInputs;
    ServiceConfig serviceConfig;
}

struct BoundData {
    address senderAddress;
    uint256 chainId;
    string customData;
}

/// @dev UNVERIFIED: helper functions as documented in onchain.md.
interface IZKPassportHelper {
    function verifyScopes(bytes32[] calldata publicInputs, string calldata domain, string calldata scope)
        external
        pure
        returns (bool);

    function getBoundData(bytes calldata committedInputs) external pure returns (BoundData memory);

    function getProofTimestamp(bytes32[] calldata publicInputs) external pure returns (uint256);
}

/// @dev UNVERIFIED: ZKPassport RootVerifier entry point as documented in onchain.md.
interface IZKPassportVerifier {
    function verify(ProofVerificationParams calldata params)
        external
        returns (bool verified, bytes32 uniqueIdentifier, IZKPassportHelper helper);
}

// ---------------------------------------------------------------------
// Human Registry
// ---------------------------------------------------------------------

contract HumanRegistry {
    // ----- Constants -------------------------------------------------

    /// @notice The ZKPassport "scope" (subscope) every proof must be made for.
    string public constant SCOPE = "lightchain-human-registry";

    /// @dev Nullifier type values from ZKPassport's API docs (UNVERIFIED):
    ///      0 = NON_SALTED, 1 = SALTED, 2 = NON_SALTED_MOCK, 3 = SALTED_MOCK, 4 = NONE.
    uint256 private constant NULLIFIER_NON_SALTED = 0;
    uint256 private constant NULLIFIER_SALTED = 1;
    /// @dev Position of nullifier_type counted from the END of publicInputs (UNVERIFIED).
    uint256 private constant NULLIFIER_TYPE_OFFSET_FROM_END = 4;
    /// @dev ZKPassport docs: "All mock passport proofs have 1 as unique identifier."
    bytes32 private constant MOCK_NULLIFIER = bytes32(uint256(1));

    uint256 public constant MIN_VALIDITY = 5 minutes;
    uint256 public constant MAX_VALIDITY = 7 days;
    uint256 public constant MIN_VERIFIER_DELAY = 2 days;

    // ----- Immutable config ------------------------------------------

    /// @notice The website domain the proofs are requested from. It is part of
    ///         every nullifier, so it can never change for this registry.
    string public domain;

    /// @notice keccak256 of the custom-data chain tag (e.g. "lightchain:9200"),
    ///         used when the ZKPassport SDK can't bind Lightchain's chain id directly.
    bytes32 public immutable chainTagHash;

    /// @notice Delay before a proposed verifier change can take effect.
    uint256 public immutable verifierDelay;

    // ----- Admin-controlled config -----------------------------------

    address public admin;
    address public pendingAdmin;

    IZKPassportVerifier public verifier;
    address public pendingVerifier;
    uint256 public pendingVerifierEta; // 0 = no pending change

    /// @notice Optional registration fee in native LCAI (wei). Default 0.
    uint256 public fee;

    /// @notice How old a proof may be when submitted.
    uint256 public validityPeriod;

    // ----- Registry state --------------------------------------------

    mapping(bytes32 nullifier => address wallet) public walletOf;
    mapping(address wallet => bytes32 nullifier) public nullifierOf;
    /// @dev Timestamp of the last proof used for a nullifier. Blocks replaying an
    ///      older proof to move a badge back to a lost or stolen wallet.
    mapping(bytes32 nullifier => uint256 proofTime) public lastProofTime;

    uint256 public humanCount;

    // ----- Events ----------------------------------------------------

    event HumanRegistered(address indexed wallet, bytes32 indexed nullifier);
    event BadgeMoved(address indexed fromWallet, address indexed toWallet, bytes32 indexed nullifier);
    event FeeChanged(uint256 oldFee, uint256 newFee);
    event ValidityPeriodChanged(uint256 oldPeriod, uint256 newPeriod);
    event FeesWithdrawn(address indexed to, uint256 amount);
    event AdminTransferStarted(address indexed currentAdmin, address indexed pendingAdmin);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event VerifierChangeProposed(address indexed newVerifier, uint256 eta);
    event VerifierChangeCancelled(address indexed cancelledVerifier);
    event VerifierChanged(address indexed oldVerifier, address indexed newVerifier);

    // ----- Errors ----------------------------------------------------

    error NotAdmin();
    error NotPendingAdmin();
    error ZeroAddress();
    error WrongFee(uint256 expected, uint256 sent);
    error ProofInvalid();
    error WrongScope();
    error NotBoundToSender();
    error WrongChain();
    error MockOrMissingNullifier();
    error AlreadyVerifiedHuman(address currentWallet);
    error WalletAlreadyHasBadge();
    error StaleProof();
    error BadValidityPeriod();
    error DelayTooShort();
    error NoPendingVerifier();
    error TimelockNotElapsed(uint256 eta);
    error TransferFailed();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    /**
     * @param _admin          Initial admin (should later hand over to the DAO).
     * @param _verifier       Address of a deployed ZKPassport RootVerifier on this chain.
     * @param _domain         Permanent website domain used for proof requests.
     * @param _chainTag       Custom-data chain tag, e.g. "lightchain:9200".
     * @param _verifierDelay  Timelock for verifier changes (>= 2 days).
     * @param _validityPeriod Max proof age in seconds (5 minutes .. 7 days).
     */
    constructor(
        address _admin,
        address _verifier,
        string memory _domain,
        string memory _chainTag,
        uint256 _verifierDelay,
        uint256 _validityPeriod
    ) {
        if (_admin == address(0) || _verifier == address(0)) revert ZeroAddress();
        if (_verifierDelay < MIN_VERIFIER_DELAY) revert DelayTooShort();
        if (_validityPeriod < MIN_VALIDITY || _validityPeriod > MAX_VALIDITY) revert BadValidityPeriod();

        admin = _admin;
        verifier = IZKPassportVerifier(_verifier);
        domain = _domain;
        chainTagHash = keccak256(bytes(_chainTag));
        verifierDelay = _verifierDelay;
        validityPeriod = _validityPeriod;
        // fee defaults to 0
    }

    // =================================================================
    // Registration
    // =================================================================

    /**
     * @notice Register (or move) a verified-human badge to msg.sender.
     * @param params      ZKPassport proof parameters from the SDK
     *                    (getSolidityVerifierParameters, mode "compressed-evm").
     *                    params.serviceConfig is IGNORED: this contract builds its
     *                    own config (fixed domain, fixed scope, devMode = false).
     * @param moveIfExists If this passport already has a badge on another wallet:
     *                    false = revert with AlreadyVerifiedHuman (the default case);
     *                    true  = move the badge here and switch off the old wallet
     *                            (the lost-wallet case).
     */
    function register(ProofVerificationParams calldata params, bool moveIfExists) external payable {
        if (msg.value != fee) revert WrongFee(fee, msg.value);
        (bytes32 nullifier, uint256 proofTime) = _checkProof(params);
        _bindOrMove(nullifier, proofTime, moveIfExists);
    }

    /// @dev Steps 1–6: verify the proof and all bindings. Split out to avoid stack-too-deep.
    function _checkProof(ProofVerificationParams calldata params)
        internal
        returns (bytes32 nullifier, uint256 proofTime)
    {
        bytes32[] calldata publicInputs = params.proofVerificationData.publicInputs;

        // 1. Verify with OUR service config. Never trust caller-supplied devMode/scope.
        ProofVerificationParams memory p = ProofVerificationParams({
            version: params.version,
            proofVerificationData: params.proofVerificationData,
            committedInputs: params.committedInputs,
            serviceConfig: ServiceConfig({
                validityPeriodInSeconds: validityPeriod,
                domain: domain,
                scope: SCOPE,
                devMode: false
            })
        });
        bool verified;
        IZKPassportHelper helper;
        (verified, nullifier, helper) = verifier.verify(p);
        if (!verified) revert ProofInvalid();

        // 2. Scope check (belt and braces; the verifier also checks scopes).
        if (!helper.verifyScopes(publicInputs, domain, SCOPE)) revert WrongScope();

        // 3. Reject mock / "no identifier" proofs (UNVERIFIED index layout).
        {
            uint256 nType = uint256(publicInputs[publicInputs.length - NULLIFIER_TYPE_OFFSET_FROM_END]);
            if (nType != NULLIFIER_NON_SALTED && nType != NULLIFIER_SALTED) revert MockOrMissingNullifier();
        }
        if (nullifier == bytes32(0) || nullifier == MOCK_NULLIFIER) revert MockOrMissingNullifier();

        // 4. Wallet binding: the proof must name msg.sender.
        {
            BoundData memory bound = helper.getBoundData(params.committedInputs);
            if (bound.senderAddress != msg.sender) revert NotBoundToSender();

            // 5. Chain binding: either the chain id, or the custom-data tag
            //    (the ZKPassport SDK's chain list does not include Lightchain).
            if (bound.chainId != block.chainid && keccak256(bytes(bound.customData)) != chainTagHash) {
                revert WrongChain();
            }
        }

        // 6. Freshness against replay: each new use of a nullifier needs a newer proof.
        //    (ZKPassport's verifier separately enforces the validity period.)
        proofTime = helper.getProofTimestamp(publicInputs);
        if (proofTime <= lastProofTime[nullifier]) revert StaleProof();
    }

    /// @dev Step 7: bind a new badge, or move an existing one.
    function _bindOrMove(bytes32 nullifier, uint256 proofTime, bool moveIfExists) internal {
        address current = walletOf[nullifier];
        bytes32 senderNullifier = nullifierOf[msg.sender];

        if (current == msg.sender) {
            // Same passport, same wallet: nothing to change.
            revert AlreadyVerifiedHuman(current);
        }
        // One badge per wallet: a wallet can't hold badges from two documents.
        if (senderNullifier != bytes32(0)) revert WalletAlreadyHasBadge();

        lastProofTime[nullifier] = proofTime;

        if (current == address(0)) {
            walletOf[nullifier] = msg.sender;
            nullifierOf[msg.sender] = nullifier;
            humanCount += 1;
            emit HumanRegistered(msg.sender, nullifier);
        } else {
            if (!moveIfExists) revert AlreadyVerifiedHuman(current);
            delete nullifierOf[current];
            walletOf[nullifier] = msg.sender;
            nullifierOf[msg.sender] = nullifier;
            emit BadgeMoved(current, msg.sender, nullifier);
        }
    }

    // =================================================================
    // Views
    // =================================================================

    /// @notice True if `wallet` currently holds a verified-human badge.
    function isHuman(address wallet) external view returns (bool) {
        return nullifierOf[wallet] != bytes32(0);
    }

    // =================================================================
    // Admin: fee and validity
    // =================================================================

    /// @notice Set the optional registration fee (wei). The DAO decides the amount.
    function setFee(uint256 newFee) external onlyAdmin {
        emit FeeChanged(fee, newFee);
        fee = newFee;
    }

    function setValidityPeriod(uint256 newPeriod) external onlyAdmin {
        if (newPeriod < MIN_VALIDITY || newPeriod > MAX_VALIDITY) revert BadValidityPeriod();
        emit ValidityPeriodChanged(validityPeriod, newPeriod);
        validityPeriod = newPeriod;
    }

    function withdrawFees(address payable to) external onlyAdmin {
        if (to == address(0)) revert ZeroAddress();
        uint256 amount = address(this).balance;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit FeesWithdrawn(to, amount);
    }

    // =================================================================
    // Admin: two-step handover (e.g. to the DAO timelock)
    // =================================================================

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        pendingAdmin = newAdmin;
        emit AdminTransferStarted(admin, newAdmin);
    }

    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPendingAdmin();
        emit AdminTransferred(admin, msg.sender);
        admin = msg.sender;
        pendingAdmin = address(0);
    }

    // =================================================================
    // Admin: timelocked verifier change
    // =================================================================

    function proposeVerifier(address newVerifier) external onlyAdmin {
        if (newVerifier == address(0)) revert ZeroAddress();
        pendingVerifier = newVerifier;
        pendingVerifierEta = block.timestamp + verifierDelay;
        emit VerifierChangeProposed(newVerifier, pendingVerifierEta);
    }

    function cancelVerifierChange() external onlyAdmin {
        if (pendingVerifierEta == 0) revert NoPendingVerifier();
        emit VerifierChangeCancelled(pendingVerifier);
        pendingVerifier = address(0);
        pendingVerifierEta = 0;
    }

    /// @notice Anyone can execute a proposed change once the delay has passed.
    function executeVerifierChange() external {
        if (pendingVerifierEta == 0) revert NoPendingVerifier();
        if (block.timestamp < pendingVerifierEta) revert TimelockNotElapsed(pendingVerifierEta);
        emit VerifierChanged(address(verifier), pendingVerifier);
        verifier = IZKPassportVerifier(pendingVerifier);
        pendingVerifier = address(0);
        pendingVerifierEta = 0;
    }
}
