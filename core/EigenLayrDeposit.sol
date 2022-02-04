import "../interfaces/IERC20.sol";
import "../interfaces/IDepositContract.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract EigenLayrDeposit {
    bytes32 public withdrawalCredentials;
    IDepositContract depositContract;
    mapping(IERC20 => bool) public isAllowedLiquidStakedToken;
    uint256 constant DEPOSIT_CONTRACT_TREE_DEPTH = 32;
    bytes32[DEPOSIT_CONTRACT_TREE_DEPTH] zero_hashes;

    constructor(IDepositContract _depositContract) {
        withdrawalCredentials =
            (bytes32(uint256(1)) << 62) |
            bytes32(bytes20(address(this))); //0x010000000000000000000000THISCONTRACTADDRESSHEREFORTHELAST20BYTES
        depositContract = _depositContract;
        // Compute hashes in empty sparse Merkle tree
        for (
            uint256 height = 0;
            height < DEPOSIT_CONTRACT_TREE_DEPTH - 1;
            height++
        )
            zero_hashes[height + 1] = sha256(
                abi.encodePacked(zero_hashes[height], zero_hashes[height])
            );
    }

    // 
    function depositETHIntoLiquidStaking(IERC20 liquidStakeToken)
        external
        payable
    {
        require(
            isAllowedLiquidStakedToken[liquidStakeToken],
            "Liquid staking token is not allowed"
        );
        uint256 deposit = liquidStakeToken.balanceOf(address(this)); // stETH balance before deposit
        Address.sendValue(payable(address(liquidStakeToken)), msg.value);
        deposit = liquidStakeToken.balanceOf(address(this)) - deposit; // increment in stETH balance
        // jeffC do your magic here
    }

    // proves the a deposit with given parameters is present in the consensus layer
    function proveConsensusLayerDeposit(
        bytes32[] calldata treeProof,
        bool[] calldata branchFlags,
        bytes32[] calldata branchProof,
        bool[] calldata leftRightFlags,
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        uint64 stake
    ) external {
        bytes32 depositRoot = depositContract.get_deposit_root();
        bytes32 node = treeProof[0];
        bytes memory sizeBytes = depositContract.get_deposit_count();
        require(
            sha256(
                abi.encodePacked(
                    node,
                    depositContract.get_deposit_count(),
                    bytes24(0)
                )
            ) == depositRoot,
            "Deposit root different from proof"
        );

        // run root contruction backward till we get the branch we want
        uint256 treeProofIndex = 1;
        for (uint256 index = 0; index < branchFlags.length; index++) {
            if (branchFlags[index]) {
                require(
                    node ==
                        sha256(
                            abi.encodePacked(
                                treeProof[treeProofIndex], //branch
                                treeProof[treeProofIndex + 1] // prev node
                            )
                        ),
                    "Branch or node preimage provided are incorrect"
                );
                node = treeProof[treeProofIndex + 1];
                treeProofIndex += 2;
            } else {
                require(
                    node ==
                        sha256(
                            abi.encodePacked(
                                treeProof[treeProofIndex], //prev node
                                zero_hashes[
                                    DEPOSIT_CONTRACT_TREE_DEPTH - index - 1
                                ] // zero level
                            )
                        ),
                    "Node preimage provided is incorrect"
                );
                node = treeProof[treeProofIndex];
                treeProofIndex += 1;
            }
        }

        // "binary hash search" the deposit root in question out of the branch
        bytes32 branchNode = treeProof[treeProofIndex - 1]; // get the branch from the last step of the proof (make sure that last step is branch step?)
        uint256 branchProofIndex = 0;
        for (uint256 index = 0; index < leftRightFlags.length; index++) {
            require(
                branchNode ==
                    sha256(
                        abi.encodePacked(
                            branchProof[branchProofIndex],
                            branchProof[branchProofIndex + 1]
                        )
                    ),
                "Hash of branches is incorrect"
            );
            if (leftRightFlags[index]) {
                branchNode = branchProof[branchProofIndex];
            } else {
                branchNode = branchProof[branchProofIndex + 1];
            }
            branchProofIndex += 2;
        }

        bytes32 pubkey_root = sha256(abi.encodePacked(pubkey, bytes16(0)));
        bytes32 signature_root = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(signature[:64])),
                sha256(abi.encodePacked(signature[64:], bytes32(0)))
            )
        );
        require(
            branchNode ==
                sha256(
                    abi.encodePacked(
                        sha256(
                            abi.encodePacked(
                                pubkey_root,
                                withdrawal_credentials
                            )
                        ),
                        sha256(
                            abi.encodePacked(
                                to_little_endian_64(stake),
                                bytes24(0),
                                signature_root
                            )
                        )
                    )
                )
        );
        // jeffC, they are pointing to a deposit of "stake" amount in Consensus Layer, with the passed pubkey, withdrawal credentials, and signature
    }

    function depositETHIntoConsensusLayer(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) external payable {
        depositContract.deposit{value: msg.value}(
            pubkey,
            abi.encodePacked(withdrawalCredentials),
            signature,
            deposit_data_root
        );
        // jeffC, they deposited msg.value ETH into Consensus Layer
    }

    function to_little_endian_64(uint64 value)
        internal
        pure
        returns (bytes memory ret)
    {
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(value);
        // Byteswapping during copying to bytes.
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }
}
