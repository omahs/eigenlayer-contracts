// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrServiceManager.sol";
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

contract DataLayrVoteWeigher is VoteWeigherBase, RegistrationManagerBaseMinusRepository, DSTest {
    using BytesLib for bytes;
    uint256 constant MODULUS = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    /**
     * @notice  Details on DataLayr nodes that would be used for -
     *           - sending data by the sequencer
     *           - querying by any challenger/retriever
     *           - payment and associated challenges
     */
    struct Registrant {
        bytes32 pubkeyHash;
        // id is always unique
        uint32 id;
        // corresponds to position in registrantList
        uint64 index;
        //
        uint48 fromDumpNumber;
        uint32 to;
        uint8 active; //bool
        // socket address of the DataLayr node
        string socket;
    }

    /**
     * @notice pack two uint48's into a storage slot
     */
    struct Uint48xUint48 {
        uint48 a;
        uint48 b;
    }

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId)");
    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant REGISTRATION_TYPEHASH = keccak256("Registration(address operator,address registrationContract,uint256 expiry)");
    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    // the latest UTC timestamp at which a DataStore expires
    uint32 public latestTime;
    
    uint32 public nextRegistrantId;
    uint128 public dlnEthStake = 1 wei;
    uint128 public dlnEigenStake = 1 wei;

    // Register, everyone is active in the list
    mapping(address => Registrant) public registry;
    address[] public registrantList;

    //operators pkh to the history of thier stake updates
    mapping(bytes32 => OperatorStake[]) public pubkeyHashToStakeHistory;

    struct OperatorStake {
        uint32 dumpNumber;
        uint32 nextUpdateDumpNumber;
        uint96 ethStake;
        uint96 eigenStake;
    }

    //the dump number in which the apk is updated
    APKUpdateMetaData[] public apkUpdates;

    struct APKUpdateMetaData {
        bool yParity;
        uint32 dumpNumber;
    }

    //list of keccak256(apk_x, apk_y) at update times
    uint256[] public apkXCoordinates;

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
    ) VoteWeigherBase(_repository, _delegation, _investmentManager, _consensusLayerEthToEth, _strategiesConsidered) {
        //apk_0 = 0
        apkUpdates.push(APKUpdateMetaData(false, 0));
        apkXCoordinates.push(0);
        //initialize the DOMAIN_SEPARATOR for signatures
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid));
    }

    /**
     * @notice returns the total Eigen delegated by delegators with this operator
     */
    /**
     * @dev minimum delegation limit has to be satisfied.
     */
    function weightOfOperatorEigen(address operator)
        public override
        view
        returns (uint128)
    {
        uint128 eigenAmount = super.weightOfOperatorEigen(operator);

        // check that minimum delegation limit is satisfied
        return eigenAmount < dlnEigenStake ? 0 : eigenAmount;
    }

    /**
     * @notice returns the total ETH delegated by delegators with this operator.
     */
    /**
     * @dev Accounts for both ETH used for staking in settlement layer (via operator)
     *      and the ETH-denominated value of the shares in the investment strategies.
     *      Note that the DataLayr can decide for itself how much weight it wants to
     *      give to the ETH that is being used for staking in settlement layer.
     */
    function weightOfOperatorEth(address operator) public override returns (uint128) {
        uint128 amount = super.weightOfOperatorEth(operator);

        // check that minimum delegation limit is satisfied
        return amount < dlnEthStake ? 0 : amount;
    }

    /**
     * @notice Used for notifying that operator wants to deregister from being 
     *         a DataLayr node 
     */
    function commitDeregistration() external returns (bool) {
        require(
            registry[msg.sender].active > 0,
            "Operator is already registered"
        );
        
        // they must store till the latest time a dump expires
        registry[msg.sender].to = latestTime;

        // committing to not signing off on any more data that is being asserted into DataLayr
        registry[msg.sender].active = 0;
        //clear stake history so cant be subtracted from apk
        pubkeyHashToStakeHistory[registry[msg.sender].pubkeyHash] = [];

        emit DeregistrationCommit(msg.sender);
        return true;
    }


    /**
     * @notice Used by an operator to de-register itself from providing service to the middleware.
     */
// TODO: decide if address input is necessary for the standard
// TODO: JEFFC -- delete operator out of stakes object (replace them with the last person & pop off the data)
    function deregisterOperator(address, bytes calldata)
        external
        returns (bool)
    {
        address operator = msg.sender;
        // TODO: verify this check is adequate
        require(
            registry[operator].to != 0 ||
                registry[operator].to < block.timestamp,
            "Operator is already registered"
        );

        // subtract the staked Eigen and ETH of the operator that is getting deregistered
        // from the total stake securing the middleware
        totalStake.ethAmount -= operatorStakes[operator].ethAmount;
        totalStake.eigenAmount -= operatorStakes[operator].eigenAmount;

        // clear the staked Eigen and ETH of the operator which is getting deregistered
        operatorStakes[operator].ethAmount = 0;
        operatorStakes[operator].eigenAmount = 0;

        //decrement number of registrants
        unchecked {
            --numRegistrants;
        }

        return true;
    }

    /**
     * @notice Used for updating information on ETH and EIGEN deposits of DataLayr nodes. 
     */
    /**
     * @param operators are the DataLayr nodes whose information on their ETH and EIGEN deposits
     *        getting updated
     */ 
    function updateStakes(
        address[] calldata operators
    ) public {
        // get current dump number from DataLayrServiceManager
        uint32 currentDumpNumber = IDataLayrServiceManager(
            address(repository.serviceManager())
        ).dumpNumber();

        uint256 operatorsLength = operators.length;

        // iterating over all the tuples that are to be updated
        for (uint256 i = 0; i < operatorsLength; ) {
            bytes32 pubkeyHash = registry[operators[i]].pubkeyHash;
            // determine current stakes
            OperatorStake memory currentStakes = pubkeyHashToStakeHistory[pubkeyHash][pubkeyHashToStakeHistory[pubkeyHash].length - 1];

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
            pubkeyHashToStakeHistory[pubkeyHash][pubkeyHashToStakeHistory[pubkeyHash].length - 1].nextUpdateDumpNumber = currentDumpNumber;
            // push new stake to storage
            pubkeyHashToStakeHistory[pubkeyHash].push(newStakes);
            // update the total stake
            totalStake.ethAmount = totalStake.ethAmount + newStakes.ethStake - currentStakes.eigenStake;
            totalStake.eigenAmount = totalStake.eigenAmount + newStakes.ethStake - currentStakes.eigenStake;
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
        returns (uint48)
    {
        return registry[operator].fromDumpNumber;
    }

    function setDlnEigenStake(uint128 _dlnEigenStake) public onlyRepositoryGovernance {
        dlnEigenStake = _dlnEigenStake;
    }

    function setDlnEthStake(uint128 _dlnEthStake) public onlyRepositoryGovernance {
        dlnEthStake = _dlnEthStake;
    }

    function setLatestTime(uint32 _latestTime) public {
        require(
            address(repository.serviceManager()) == msg.sender,
            "service manager can only call this"
        ); if (_latestTime > latestTime) {
            latestTime = _latestTime;            
        }
    }

    function getOperatorId(address operator) public view returns (uint32) {
        return registry[operator].id;
    }

    /// @notice returns the type for the specified operator
    function getOperatorType(address operator)
        public
        view
        returns (uint8)
    {
        return registry[operator].active;
    }

    function getCorrectCompressedApk(uint256 index, uint32 dumpNumberToConfirm) public view returns(bytes memory) {
        APKUpdateMetaData memory apkUpdate = apkUpdates[index];
        require(dumpNumberToConfirm >= apkUpdate.dumpNumber, "Index too recent");
        //if not last update
        if(index != apkUpdates.length - 1) {
            require(dumpNumberToConfirm < apkUpdates[index + 1], "Not latest valid apk update");
        }
        uint256 apk_x = apkXCoordinates[index];
        bool yParity = apkUpdate.yParity;
        bytes memory compressed;
        assembly {
            mstore(compressed, apk_x)
            mstore(add(compressed, 32), yParity)
        }
        return compressed;
    }

    function getCompressedApk() public view returns(bytes memory) {
        uint256 updateLength = apkUpdates.length - 1;
        uint256 apk_x = apkXCoordinates[updateLength];
        bool yParity = apkUpdates[updateLength].yParity;
        bytes memory compressed;
        assembly {
            mstore(compressed, apk_x)
            mstore(add(compressed, 32), yParity)
        }
        return compressed;
    }





    function registerOperator(uint8 registrantType, string calldata socket, bytes calldata data) public {
        _registerOperator(msg.sender, registrantType, socket, data);
    }

    function _registerOperator(address operator, uint8 registrantType, string calldata socket, bytes calldata data) internal {
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
            require(_operatorStake.ethStake >= dlnEthStake, "Not enough eth value staked");
        }

        //if second bit of registrantType is '1', then operator wants to be an EIGEN validator
        if ((registrantType & 2) == 2) {
            // if operator want to be an "Eigen" validator, check that they meet the 
            // minimum requirements on how much Eigen it must deposit
            _operatorStake.eigenStake = uint96(weightOfOperatorEigen(operator));
            require(_operatorStake.eigenStake >= dlnEigenStake, "Not enough eigen staked");
        }

        require(_operatorStake.ethStake > 0 || _operatorStake.eigenStake > 0, "must register as at least one type of validator");

        // get current dump number from DataLayrServiceManager
        uint32 currentDumpNumber = IDataLayrServiceManager(
            address(repository.serviceManager())
        ).dumpNumber();

        //verify sig of public key and get pubkeyHash back, slice out compressed apk
        (uint256 pk_x, uint256 pk_y) = BLS.verifyBLSSigOfPubKeyHash(data);

        bytes32 pubkeyHash = keccak256(abi.encodePacked(pk_x, pk_y));

        //get coors of apk
        bytes memory compressed = getCompressedApk();
        (uint256 apk_x, uint256 apk_y) = decompressPublicKey(compressed);

        //add new public key to apk
        uint256[] memory input = new uint256[](4);
        input[0] = pk_x;
        input[1] = pk_y;
        input[2] = apk_x;
        input[3] = apk_y;

        //overwrite first to indexes of input with new apk
        assembly {
            if iszero(call(not(0), 0x06, 0, input, 0x80, input, 0x40)) {
                revert(0, 0)
            }
        }

        //update apk coordinates
        apkUpdates.push(
            APKUpdateMetaData(
                getYParity(input[0], input[1]), 
                currentDumpNumber
            )
        );
        apkXCoordinates.push(input[0]);

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
    }

    function decompressPublicKey(bytes memory compressed) internal returns(uint256, uint256) {
        uint256 x;
        uint256 y;
        uint256[] memory input;
        assembly {
            //x is the first 32 bytes of compressed
            x := mload(compressed)
            x := mod(x, MODULUS)
            // y = x^2 mod m
            y := mulmod(x, x, MODULUS)
            // y = x^3 mod m
            y := mulmod(y, x, MODULUS)
            // y = x^3 + 3 mod m
            y := addmod(y, 3, MODULUS)
            //really the elliptic curve equation is y^2 = x^3 + 3 mod m
            //so we have y^2 stored as y, so let's find the sqrt

            // (y^2)^((MODULUS + 1)/4) = y
            // base of exponent is y
            mstore(
                input,
                32 // y is 32 bytes long
            )
            // the exponent (MODULUS + 1)/4 is also 32 bytes long
            mstore(
                add(input, 0x20),
                32
            )
            // MODULUS is 32 bytes long
            mstore(
                add(input, 0x40),
                32
            )
            // base is y
            mstore(
                add(input, 0x60),
                y
            )
            // exponent is (N + 1) / 4 = 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            mstore(
                add(input, 0x80),
                0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            )
            //MODULUS
            mstore(
                add(input, 0xA0),
                MODULUS
            )
            //store sqrt(y^2) as y
            if iszero(
                call(not(0), 0x05, 0, input, 0x12, y, 0x20)
            ) {
                revert(0, 0)
            }
        }
        //use 33rd byte as toggle for the sign of sqrt
        //because y and -y are both solutions
        if(compressed[32] != 0) {
            y = MODULUS - y;
        }
        return (x, y);
    }

    function getYParity(uint256 x, uint256 yExpected) internal returns(bool) {
        uint256 y;
        uint256[] memory input;
        assembly {
            //x is the first 32 bytes of compressed
            x := mload(compressed)
            x := mod(x, MODULUS)
            // y = x^2 mod m
            y := mulmod(x, x, MODULUS)
            // y = x^3 mod m
            y := mulmod(y, x, MODULUS)
            // y = x^3 + 3 mod m
            y := addmod(y, 3, MODULUS)
            //really the elliptic curve equation is y^2 = x^3 + 3 mod m
            //so we have y^2 stored as y, so let's find the sqrt

            // (y^2)^((MODULUS + 1)/4) = y
            // base of exponent is y
            mstore(
                input,
                32 // y is 32 bytes long
            )
            // the exponent (MODULUS + 1)/4 is also 32 bytes long
            mstore(
                add(input, 0x20),
                32
            )
            // MODULUS is 32 bytes long
            mstore(
                add(input, 0x40),
                32
            )
            // base is y
            mstore(
                add(input, 0x60),
                y
            )
            // exponent is (N + 1) / 4 = 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            mstore(
                add(input, 0x80),
                0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            )
            //MODULUS
            mstore(
                add(input, 0xA0),
                MODULUS
            )
            //store sqrt(y^2) as y
            if iszero(
                call(not(0), 0x05, 0, input, 0x12, y, 0x20)
            ) {
                revert(0, 0)
            }
        }
        //if y == yExpected, then the yParity is true, y is positive, otherwise it needs to be negated
        return y == yExpected;
    }
}