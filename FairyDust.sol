pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FairyDust is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 public constant supply = 333555888000000000000000000;
    uint256 public totalInitialAllocation = 0;
    
    // maximal locks count (to prevent OUT_OF_GAS error on call _unlockTokens method)
    // for unlock 54 items ~600000 gas used
    uint256 public constant MAX_LOCK = 50;
    
    // Initial allocation params
    bool private _initialAllocationComplete = false;
    mapping(address => uint256) internal _initialAllocationValue;
    mapping(uint => address) internal _initialAllocationAddresses;
    mapping(address => uint) internal _initialAllocationIndex;
    uint256 internal _initialAllocationCount = 0;
    
    // @ ERC20 internals
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    // locked tokens entry
    struct Lock {
        uint256 amount; // how many tokens is locked
        uint256 toTime; // lock deadline
    }
    
    // locked tokens list
    mapping(address => Lock[]) private _lockedTokens;
    
    // locking events
    event LockTokens(address indexed account, address indexed to, uint256 value, uint256 toTime);
    event UnlockTokens(address indexed account, uint256 value);

    constructor() ERC20("FairyDust", "FD") {
        
    }

    function decimals() public view virtual override returns (uint8) {
       return 18;
    }
    
    // lock tokens for given user to given timestamp
    // if given user is not msg.sender emits Transfer event
    function _lockTokens(address to, uint256 value, uint256 toTime) internal {
        require(_lockedTokens[to].length <= MAX_LOCK, "exceed lock pool limit");
        require(toTime > block.timestamp, "lock end time must be after current time");

        uint256 senderBalance = _balances[_msgSender()];
        require(senderBalance >= value, "ERC20: lock amount exceeds balance");
        unchecked {
            _balances[_msgSender()] = senderBalance - value;
        }

        if (_msgSender() != to)
            emit Transfer(_msgSender(), to, value); // if you lock tokens for other account need to emit Transfer event

        _lockedTokens[to].push(Lock(value, toTime));
        emit LockTokens(_msgSender(), to, value, toTime);
    }

    // lock tokens to given timeout (in seconds)
    function lockTokens(uint256 value, uint256 timeout) public {
        _lockTokens(_msgSender(), value, block.timestamp + timeout);
    }

    // lock tokens to given timeout (in seconds)
    // this tokens can be unlocked with {to} account only, and looks like default token transfer
    function lockTokensTo(address to, uint256 value, uint256 timeout) public {
        _lockTokens(to, value, block.timestamp + timeout);
    }

    // lock tokens to given timestamp
    function lockTokensBefore(uint256 value, uint256 timestamp) public {
        _lockTokens(_msgSender(), value, timestamp);
    }

    // lock tokens to given timestamp
    // this tokens can be unlocked with {to} account only, and looks like default token transfer
    function lockTokensToBeforeTime(address to, uint256 value, uint256 timestamp) public {
        _lockTokens(to, value, timestamp);
    }

    // returns total locked tokens in {user} wallet
    function totalLocked(address account) public view returns(uint256 total) {
        if (_lockedTokens[account].length > 0) {
            for (uint i = 0; i < _lockedTokens[account].length; i++)
                total += _lockedTokens[account][i].amount;
        }
    }

    // returns total locked tokens in {account} wallet, available to unlock
    function canBeUnlocked(address account) public view returns(uint256 total) {
        if (_lockedTokens[account].length > 0)
            for (uint i = 0; i < _lockedTokens[account].length; i++)
                if (_lockedTokens[account][i].toTime <= block.timestamp)
                    total += _lockedTokens[account][i].amount;
    }

    // returns locked token entries list for given account
    function getUserLocks(address account) public view returns(Lock[] memory locks) {
        locks = _lockedTokens[account];
    }

    // unlocks token for given wallet. 
    function unlockTokensForAddress(address account) public returns(uint256 totalUnlocked) {
        require(_lockedTokens[account].length > 0, "no tokens locked");
        uint i = 0;                                                     // <-- current array index
        while(i < _lockedTokens[account].length) {                      // while current array index smaller than array length
            if (_lockedTokens[account][i].toTime <= block.timestamp) {  // check for lock time expiration, if expired:
                totalUnlocked += _lockedTokens[account][i].amount;      // add amount to total value
                if (i == _lockedTokens[account].length-1) {             // is last array element?
                    _lockedTokens[account].pop();                       // then remove it
                    break;                                              // and break loop
                } else {                                                // if not - copy last array element to current index
                    _lockedTokens[account][i] = _lockedTokens[account][_lockedTokens[account].length-1]; // <-- there
                    _lockedTokens[account].pop();                       // and remove last array element
                }                                                       // (pop operation decreases array.length)
            } else {                                                    // if lock time is not expired
                i++;                                                    // move to next array index
            }                                                           // and return to <while> condition
        }

        require(totalUnlocked > 0, "no unlocked tokens now");

        // issue locked tokens to user's balance
        _balances[account] += totalUnlocked;
        emit UnlockTokens(account, totalUnlocked);
    }

    // unlock tokens for sender address
    function unlockTokens() public returns(uint256 totalUnlocked) {
        return unlockTokensForAddress(_msgSender());
    }
    
    /**
     *  @dev do initital token allocation
     */
    function initialAllocation() public onlyOwner {
        require(!_initialAllocationComplete, "initial allocation complete");
        _initialAllocationComplete = true;

        for (uint i = 0; i < _initialAllocationCount; i++) {
            _mint(_initialAllocationAddresses[i], _initialAllocationValue[_initialAllocationAddresses[i]]);
        }

        // if total allocated funds is smaller than initial supply
        // difference be minted to owner address
        if (totalInitialAllocation != supply) {
            _mint(owner(), supply - totalInitialAllocation);
        }
    }

    /**
     * add given address to initial allocation list
     */
    function addInitialAllocation(address _address, uint256 _value) public onlyOwner {
        require(!_initialAllocationComplete, "initial allocation complete");
        require(_initialAllocationValue[_address] == 0, "this address already registered, use 'setInitialAllocation' to change value");
        require(_value > 0, "_value cannot be a zero");
        require(totalInitialAllocation+_value < supply, "initial supply overflow");

        _initialAllocationAddresses[_initialAllocationCount] = _address;
        _initialAllocationValue[_address] = _value;
        _initialAllocationIndex[_address] = _initialAllocationCount;
        _initialAllocationCount++;
        totalInitialAllocation += _value;
    }

    /**
     * set initial allocation value to given address
     */
    function setInitialAllocation(address _address, uint256 _value) public onlyOwner {
        require(!_initialAllocationComplete, "initial allocation complete");
        require(_initialAllocationValue[_address] > 0, "this address is not registered, use 'addInitialAllocation' to add receiver");
        require(_value > 0, "_value cannot be a zero");

        totalInitialAllocation -= _initialAllocationValue[_address];
        require(totalInitialAllocation+_value < supply, "initial supply overflow");

        _initialAllocationValue[_address] = _value;
        totalInitialAllocation += _value;
    }

    /**
     * remove given address from initial allocation list
     */
    function removeInitialAllocation(address _address) public onlyOwner {
        require(!_initialAllocationComplete, "initial allocation complete");
        require(_initialAllocationValue[_address] > 0, "this address is not registered");

        totalInitialAllocation -= _initialAllocationValue[_address];
        delete _initialAllocationValue[_address];
        delete _initialAllocationIndex[_address];
        for (uint i = _initialAllocationIndex[_address]; i < _initialAllocationCount; i++) {
            if (i == _initialAllocationCount-1) {
                delete _initialAllocationAddresses[i];
            } else {
                _initialAllocationAddresses[i] = _initialAllocationAddresses[i+1];
                _initialAllocationIndex[_initialAllocationAddresses[i]] = i;
            }
        }

        _initialAllocationCount--;
    }
    
    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public override returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal override  {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    
    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return "FairyDust";
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return "FD";
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
}