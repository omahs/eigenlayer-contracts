// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayrVoteWeigher.sol";
import "../../libraries/BytesLib.sol";
import "../Repository.sol";
import "../VoteWeigherBase.sol";
import "../RegistrationManagerBaseMinusRepository.sol";
import "../../libraries/SignatureCompaction.sol";
import "../../libraries/BLS.sol";

import "ds-test/test.sol";

/**
 * @notice
 */

contract DataLayrVoteWeigher is
    IDataLayrVoteWeigher,
    VoteWeigherBase,
    RegistrationManagerBaseMinusRepository,
    DSTest
{
    using BytesLib for bytes;

    // CONSTANTS
    uint256 constant MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant REGISTRATION_TYPEHASH =
        keccak256(
            "Registration(address operator,address registrationContract,uint256 expiry)"
        );


    // DATA STRUCTURES 
    /**
     * @notice  Data structure for storing info on DataLayr operators that would be used for:
     *           - sending data by the sequencer
     *           - querying by any challenger/retriever
     *           - payment and associated challenges
     */
    struct Registrant {
        // hash of pubkey of the DataLayr operator
        bytes32 pubkeyHash;

        // id is always unique
        uint32 id;

        // corresponds to position in registrantList
        uint64 index;

        //
        uint32 fromDumpNumber;

        uint32 to;

        // indicates whether the DataLayr operator is actively registered for storing data or not 
        uint8 active; //bool

        // socket address of the DataLayr node
        string socket;
    }

  

    uint128 public dlnEthStake = 1 wei;
    uint128 public dlnEigenStake = 1 wei;
    
    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice the latest UTC timestamp at which a DataStore expires
    uint32 public latestTime;


    /// @notice a sequential counter that is incremented whenver new operator registers
    uint32 public nextRegistrantId;


    /// @notice used for storing Registrant info on each DataLayr operator while registration
    mapping(address => Registrant) public registry;

    /// @notice used for storing the list of current and past registered DataLayr operators 
    address[] public registrantList;


    /// @notice mapping from operator's pubkeyhash to the history of their stake updates
    mapping(bytes32 => OperatorStake[]) public pubkeyHashToStakeHistory;


    /// @notice the dump numbers in which the aggregated pubkeys are updated
    uint32[] public apkUpdates;


    /**
     @notice list of keccak256(apk_x0, apk_x1, apk_y0, apk_y1) of DataLayr operators, 
             this is updated whenever a new operator registers or deregisters
     */
    bytes32[] public apkHashes;


    // the current aggregate public key, used for uncoordinated registration
    /// @dev This is the generator of G2 group. It is necessary in order to do addition in Jacobian coordinate system.
    uint256[4] public apk = [10857046999023057135944570762232829481370756359578518086990519993285655852781,11559732032986387107991004021392285783925812861821192530917403151452391805634,8495653923123431417604973247489272438418190587263600148770280649306958101930,4082367875863433681332203403145435568316851327593401208105741076214120093531];

    

    // EVENTS
    event StakeAdded(
        address operator,
        uint96 ethStake,
        uint96 eigenStake,
        uint256 updateNumber,
        uint32 dumpNumber,
        uint32 prevDumpNumber
    );
    // uint48 prevUpdateDumpNumber

    event StakeUpdate(
        address operator,
        uint96 ethStake,
        uint96 eigenStake,
        uint32 dumpNumber,
        uint32 prevUpdateDumpNumber
    );
    event EigenStakeUpdate(
        address operator,
        uint128 stake,
        uint32 dumpNumber,
        uint32 prevUpdateDumpNumber
    );

    // MODIFIERS
    modifier onlyRepository() {
        require(address(repository) == msg.sender, "onlyRepository");
        _;
    }


    constructor(
        Repository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        uint256 _consensusLayerEthToEth,
        IInvestmentStrategy[] memory _strategiesConsidered
    )
        VoteWeigherBase(
            _repository,
            _delegation,
            _investmentManager,
            _consensusLayerEthToEth,
            _strategiesConsidered
        )
    {
        //apk_0 = g2Gen
        // initialize the DOMAIN_SEPARATOR for signatures
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid)
        );
    }

    /**
     * @notice returns the total Eigen delegated by delegators with this operator
     */
    /**
     * @dev minimum delegation limit of dlnEigenStake has to be satisfied.
     */
    function weightOfOperatorEigen(address operator)
        public
        view
        override
        returns (uint128)
    {
        uint128 eigenAmount = super.weightOfOperatorEigen(operator);

        // check that minimum delegation limit is satisfied
        return eigenAmount < dlnEigenStake ? 0 : eigenAmount;
    }

    /**
        @notice returns the total ETH delegated by delegators with this operator.
                Accounts for both ETH used for staking in settlement layer (via operator)
                and the ETH-denominated value of the shares in the investment strategies.
                Note that the DataLayr can decide for itself how much weight it wants to
                give to the ETH that is being used for staking in settlement layer.
     */
    /**
     * @dev minimum delegation limit of dlnEthStake has to be satisfied.
     */
    function weightOfOperatorEth(address operator)
        public
        override
        returns (uint128)
    {
        uint128 amount = super.weightOfOperatorEth(operator);

        // check that minimum delegation limit is satisfied
        return amount < dlnEthStake ? 0 : amount;
    }

    /**
      @notice Used by an operator to de-register itself from providing service to the middleware.
     */
    /** 
      @param pubkeyToRemoveAff is the sender's pubkey in affine coordinates
     */
    function commitDeregistration(uint256[4] memory pubkeyToRemoveAff) external returns (bool) {
        require(
            registry[msg.sender].active > 0,
            "Operator is already registered"
        );


        // must store till the latest time a dump expires
        /**
         @notice this info is used in forced disclosure
         */
        registry[msg.sender].to = latestTime;


        // committing to not signing off on any more data that is being asserted into DataLayr
        registry[msg.sender].active = 0;



        // TODO: this logic is mostly copied from 'updateStakes' function. perhaps de-duplicating it is possible
        // get current dump number from DataLayrServiceManager
        uint32 currentDumpNumber = IDataLayrServiceManager(address(repository.serviceManager())).dumpNumber();        
        

        /**
         @notice verify that the sender is a DataLayr operator that is doing deregistration for itself 
         */
        // get operator's stored pubkeyHash
        bytes32 pubkeyHash = registry[msg.sender].pubkeyHash;
        bytes32 pubkeyHashFromInput = keccak256(
            abi.encodePacked(
                pubkeyToRemoveAff[0],
                pubkeyToRemoveAff[1],
                pubkeyToRemoveAff[2],
                pubkeyToRemoveAff[3]
            )
        );
        // verify that it matches the 'pubkeyToRemoveAff' input
        require(pubkeyHash == pubkeyHashFromInput, "incorrect input for commitDeregistration");



        /**
         @notice recording the information pertaining to change in stake for this 
                 DataLayr operator in the history
         */
        // determine new stakes
        OperatorStake memory newStakes;
        // recording the current dump number where the operator stake got updated 
        newStakes.dumpNumber = currentDumpNumber;

        // setting total staked ETH for the DataLayr operator to 0
        newStakes.ethStake = uint96(0);
        // setting total staked Eigen for the DataLayr operator to 0
        newStakes.eigenStake = uint96(0);

        //set next dump number in prev stakes
        pubkeyHashToStakeHistory[pubkeyHash][
            pubkeyHashToStakeHistory[pubkeyHash].length - 1
        ].nextUpdateDumpNumber = currentDumpNumber;

        // push new stake to storage
        pubkeyHashToStakeHistory[pubkeyHash].push(newStakes);


        /**
         */
        // subtract the staked Eigen and ETH of the operator that is getting deregistered
        // from the total stake securing the middleware
        totalStake.ethAmount -= operatorStakes[msg.sender].ethAmount;
        totalStake.eigenAmount -= operatorStakes[msg.sender].eigenAmount;

        // clear the staked Eigen and ETH of the operator which is getting deregistered
        operatorStakes[msg.sender].ethAmount = 0;
        operatorStakes[msg.sender].eigenAmount = 0;

        //decrement number of registrants
        unchecked {
            --numRegistrants;
        }

        // get existing aggregate public key
        uint256[4] memory pk = apk;
        // remove signer's pubkey from aggregate public key
        pk = removePubkeyFromAggregate(pubkeyToRemoveAff, pk);
        // update stored aggregate public key
        apk = pk;

        // update apk coordinates
        apkUpdates.push(currentDumpNumber);
        //store hashed apk
        apkHashes.push(keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3])));

        emit DeregistrationCommit(msg.sender);
        return true;
    }

    function removePubkeyFromAggregate(uint256[4] memory pubkeyToRemoveAff, uint256[4] memory existingAggPubkeyAff) internal returns (uint256[4] memory) {
        uint256[6] memory pubkeyToRemoveJac;
        uint256[6] memory existingAggPubkeyJac;
        for (uint256 i = 0; i < 4;) {
            pubkeyToRemoveJac[i] = pubkeyToRemoveAff[i];
            existingAggPubkeyJac[i] = existingAggPubkeyAff[i];
            unchecked {
                ++i;
            }
        }
        pubkeyToRemoveJac[4] = 1;
        existingAggPubkeyJac[4] = 1;

        //subtract pubkeyToRemoveJac from the aggregate pubkey
        //to do this, negate pubkeyToRemoveJac first, then add the negation to existingAggPubkeyJac
        pubkeyToRemoveJac[2] = (MODULUS - pubkeyToRemoveJac[2]) % MODULUS;
        pubkeyToRemoveJac[3] = (MODULUS - pubkeyToRemoveJac[3]) % MODULUS;
        BLS.addJac(existingAggPubkeyJac, pubkeyToRemoveJac);
        // 'addJac' function above modifies the first input in memory, so now we can just return it (but first transform it back to affine)
        return (BLS.jacToAff(existingAggPubkeyJac));
    }

    /**
     * @notice Used by an operator to complete the deregistration process
     */
    function deregisterOperator()
        external
        returns (bool)
    {
        require(
            registry[msg.sender].to != 0 &&
                registry[msg.sender].to < block.timestamp,
            "Operator has not yet commited deregistration, or still has active commitments"
        );
        // TODO: REMOVE ABILITY TO SLASH THE OPERATOR ANY MORE

        return true;
    }

    /**
     * @notice Used for updating information on ETH and EIGEN deposits of DataLayr nodes.
     */
    /**
     * @param operators are the DataLayr nodes whose information on their ETH and EIGEN deposits
     *        getting updated
     */
    function updateStakes(address[] calldata operators) public {
        // get current dump number from DataLayrServiceManager
        uint32 currentDumpNumber = IDataLayrServiceManager(
            address(repository.serviceManager())
        ).dumpNumber();

        uint256 operatorsLength = operators.length;

        // iterating over all the tuples that are to be updated
        for (uint256 i = 0; i < operatorsLength; ) {
            // get operator's pubkeyHash
            bytes32 pubkeyHash = registry[operators[i]].pubkeyHash;
            // determine current stakes
            OperatorStake memory currentStakes = pubkeyHashToStakeHistory[
                pubkeyHash
            ][pubkeyHashToStakeHistory[pubkeyHash].length - 1];

            // determine new stakes
            OperatorStake memory newStakes;

            newStakes.dumpNumber = currentDumpNumber;
            newStakes.ethStake = uint96(weightOfOperatorEth(operators[i]));
            newStakes.eigenStake = uint96(weightOfOperatorEigen(operators[i]));

            // check if minimum requirements have been met
            if (newStakes.ethStake < dlnEthStake) {
                newStakes.ethStake = uint96(0);
            }
            if (newStakes.eigenStake < dlnEigenStake) {
                newStakes.eigenStake = uint96(0);
            }
            //set next dump number in prev stakes
            pubkeyHashToStakeHistory[pubkeyHash][
                pubkeyHashToStakeHistory[pubkeyHash].length - 1
            ].nextUpdateDumpNumber = currentDumpNumber;
            // push new stake to storage
            pubkeyHashToStakeHistory[pubkeyHash].push(newStakes);
            // update the total stake
            totalStake.ethAmount =
                totalStake.ethAmount +
                newStakes.ethStake -
                currentStakes.eigenStake;
            totalStake.eigenAmount =
                totalStake.eigenAmount +
                newStakes.ethStake -
                currentStakes.eigenStake;
            emit StakeUpdate(
                operators[i],
                newStakes.ethStake,
                newStakes.eigenStake,
                currentDumpNumber,
                currentStakes.dumpNumber
            );
            unchecked {
                ++i;
            }
        }
    }

    function getOperatorFromDumpNumber(address operator)
        public
        view
        returns (uint32)
    {
        return registry[operator].fromDumpNumber;
    }

    function setDlnEigenStake(uint128 _dlnEigenStake)
        public
        onlyRepositoryGovernance
    {
        dlnEigenStake = _dlnEigenStake;
    }

    function setDlnEthStake(uint128 _dlnEthStake)
        public
        onlyRepositoryGovernance
    {
        dlnEthStake = _dlnEthStake;
    }

    function setLatestTime(uint32 _latestTime) public {
        require(
            address(repository.serviceManager()) == msg.sender,
            "service manager can only call this"
        );
        if (_latestTime > latestTime) {
            latestTime = _latestTime;
        }
    }

    function getOperatorId(address operator) public view returns (uint32) {
        return registry[operator].id;
    }

    /// @notice returns the type for the specified operator
    function getOperatorType(address operator) public view returns (uint8) {
        return registry[operator].active;
    }

    function getCorrectApkHash(uint256 index, uint32 dumpNumberToConfirm)
        public
        // view
        returns (bytes32)
    {
        require(
            dumpNumberToConfirm >= apkUpdates[index],
            "Index too recent"
        );

        //if not last update
        if (index != apkUpdates.length - 1) {
            require(
                dumpNumberToConfirm < apkUpdates[index + 1],
                "Not latest valid apk update"
            );
        }
        return apkHashes[index];
    }

    function getOperatorPubkeyHash(address operator) public view returns(bytes32) {
        return registry[operator].pubkeyHash;
    }

    function getStakeFromPubkeyHashAndIndex(bytes32 pubkeyHash, uint256 index)
        public
        view
        returns (OperatorStake memory)
    {
        return pubkeyHashToStakeHistory[pubkeyHash][index];
    }

    function registerOperator(
        uint8 registrantType,
        bytes calldata data,
        string calldata socket
    ) public {
        _registerOperator(msg.sender, registrantType, data, socket);
    }

    function _registerOperator(
        address operator,
        uint8 registrantType,
        bytes calldata data,
        string calldata socket
    ) internal {
        require(
            registry[operator].active == 0,
            "Operator is already registered"
        );

        // TODO: shared struct type for this + registrantType, also used in Repository?
        OperatorStake memory _operatorStake;

        //if first bit of registrantType is '1', then operator wants to be an ETH validator
        if ((registrantType & 1) == 1) {
            // if operator want to be an "ETH" validator, check that they meet the
            // minimum requirements on how much ETH it must deposit
            _operatorStake.ethStake = uint96(weightOfOperatorEth(operator));
            require(
                _operatorStake.ethStake >= dlnEthStake,
                "Not enough eth value staked"
            );
        }

        //if second bit of registrantType is '1', then operator wants to be an EIGEN validator
        if ((registrantType & 2) == 2) {
            // if operator want to be an "Eigen" validator, check that they meet the
            // minimum requirements on how much Eigen it must deposit
            _operatorStake.eigenStake = uint96(weightOfOperatorEigen(operator));
            require(
                _operatorStake.eigenStake >= dlnEigenStake,
                "Not enough eigen staked"
            );
        }

        require(
            _operatorStake.ethStake > 0 || _operatorStake.eigenStake > 0,
            "must register as at least one type of validator"
        );

        // get current dump number from DataLayrServiceManager
        uint32 currentDumpNumber = IDataLayrServiceManager(
            address(repository.serviceManager())
        ).dumpNumber();

        uint256[4] memory newApk;
        uint256[4] memory pk;

        {
            // verify sig of public key and get pubkeyHash back, slice out compressed apk
            (pk[0], pk[1], pk[2], pk[3]) = BLS.verifyBLSSigOfPubKeyHash(data, 132);
            //add pk to apk
            uint256[6] memory newApkJac = BLS.addJac([pk[0], pk[1], pk[2], pk[3], 1, 0], [apk[0], apk[1], apk[2], apk[3], 1, 0]);
            newApk = BLS.jacToAff(newApkJac);
            apk = newApk;
        }

        bytes32 pubkeyHash = keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3]));

        if (apkUpdates.length != 0) {
            //addition doesn't work in this case
            require(pubkeyHash != apkHashes[apkHashes.length - 1], "Apk and pubkey cannot be the same");
        }

        // emit log_bytes(getCompressedApk());
        // emit log_named_uint("x", input[0]);
        // emit log_named_uint("y", getYParity(input[0], input[1]) ? 0 : 1);

        // update apk coordinates
        apkUpdates.push(currentDumpNumber);
        //store hashed apk
        bytes32 newApkHash = keccak256(abi.encodePacked(newApk[0], newApk[1], newApk[2], newApk[3]));
        apkHashes.push(newApkHash);

        _operatorStake.dumpNumber = currentDumpNumber;

        //store operatorStake in storage
        pubkeyHashToStakeHistory[pubkeyHash].push(_operatorStake);

        // slice starting the byte after socket length to construct the details on the
        // DataLayr node
        registry[operator] = Registrant({
            pubkeyHash: pubkeyHash,
            id: nextRegistrantId,
            index: numRegistrants,
            active: registrantType,
            fromDumpNumber: IDataLayrServiceManager(
                address(repository.serviceManager())
            ).dumpNumber(),
            to: 0,
            // extract the socket address
            socket: socket
        });

        // record the operator being registered
        registrantList.push(operator);

        // update the counter for registrant ID
        unchecked {
            ++nextRegistrantId;
        }

        // copy total stake to memory
        EthAndEigenAmounts memory _totalStake = totalStake;
        /**
         * update total Eigen and ETH that are being employed by the operator for securing
         * the queries from middleware via EigenLayr
         */
        _totalStake.ethAmount += _operatorStake.ethStake;
        _totalStake.eigenAmount += _operatorStake.eigenStake;
        // update storage of total stake
        totalStake = _totalStake;

        //TODO: do we need this variable at all?
        //increment number of registrants
        unchecked {
            ++numRegistrants;
        }

        emit Registration(operator, pk, uint32(apkHashes.length), newApkHash);
    }
}
