pragma solidity ^0.6.12;

contract NameRegisterSystem {

    IBEP20 public token;
    // Deposit Fee address
    address public feeAddress;

    // Info of each name.
    struct NameInfo {
        string name;
        uint256 regTime;
        uint balance;
        bool registered;
    }

    // registered name list
    mapping (address => NameInfo) public regInfos;
    mapping (string => bool) public regNameCheck;

    uint public constant LOCK_PERIOD = 14 days;
    uint public constant LOCK_AMOUNT = 1000000;

    event RegisterUser(address userAddr, string name);
    event UnregisterUser(address userAddr, uint value);

    constructor (IBEP20 _token, address public _feeAddress) public {
        token = _token;
        feeAddress = _feeAddress;
    }

    function queueTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public returns (bytes32) {
        require(eta >= getUserTimestamp(_msgSender()).add(LOCK_PERIOD), "queueTransaction: Estimated execution block must satisfy delay.");

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, target, value, signature, data, eta);
        return txHash;
    }

    function cancelTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, target, value, signature, data, eta);
    }

    function executeTransaction(address target, uint value, string memory signature, bytes memory data, uint eta) public payable returns (bytes memory) {
        require(isRegistered(msg.sender), "You are not registered");

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], "executeTransaction: Transaction hasn't been queued.");
        require(getUserTimestamp(msg.sender) >= eta, "executeTransaction: Transaction hasn't surpassed time lock.");
        require(getUserTimestamp(msg.sender) <= eta.add(LOCK_PERIOD), "Timelock::executeTransaction: Transaction is stale.");

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call.value(value)(callData);
        require(success, "executeTransaction: Transaction execution reverted.");

        emit ExecuteTransaction(txHash, target, value, signature, data, eta);

        return returnData;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        require(isRegistered(msg.sender), "You are not registered");

        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function getUserTimestamp() internal view returns (uint) {
        return regInfos[user].regTime;
    }

    function isRegistered(address user) internal view returns (uint) {
        return regInfos[user].registered;
    }

    function registerUser(string name, uint256 _amount) payable external nonReentrant {
        // check lock expired
        uint curTime = block.timestamp;
        if (isRegistered(msg.sender) && curTime >= getUserTimestamp(msg.sender).add(LOCK_PERIOD)) {
            // renew
            regNameCheck[regInfos[msg.sender].name] = false;

            regInfos[msg.sender].regTime = curTime;
            regInfos[msg.sender].name = name;

            return;
        }

        require(isRegistered(msg.sender) == false "registerUser: already registered");
        require(_amount > LOCK_AMOUNT, "registerUser: no enough");

        bytes memory string_rep = bytes(name);
        uint256 name_len = string_rep.length;
        uint256 feeBP = name_len.mul(1e3); // changable

        // lock _amount
        uint256 oldBalance = token.balanceOf(address(this));
        token.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 newBalance = token.balanceOf(address(this));
        _amount = newBalance.sub(oldBalance);

        // fee
        uint256 feeVal = _amount.mul(feeBP).div(10000);
        token.safeTransfer(feeAddress, feeVal);

        NameInfo storage info = regInfos[msg.sender];
        info.name = name;
        info.regTime = block.timestamp;
        info.balance = info.balance.add(_amount);
        info.registered = true;

        regNameCheck[name] = true;

        emit RegisterUser(msg.sender, _amount);
    }

    function unregisterUser() external {
        require(isRegistered(msg.sender), "unregisterUser: unregistered");

        NameInfo storage info = regInfos[msg.sender];

        // unlock _amount
        withdraw(info.balance);
        info.registered = false;
        regNameCheck[info.name] = false;

        emit UnregisterUser(msg.sender, _amount);
    }

    function withdraw(uint wad) internal {
        msg.sender.transfer(wad);
        regInfos[msg.sender].balance = regInfos[msg.sender].balance.sub(wad);
    }

}