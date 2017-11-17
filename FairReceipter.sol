//! Receipting contract. Just records who sent what.
//! By Parity Technologies, 2017.
//! Released under the Apache Licence 2.

pragma solidity ^0.4.7;

import "Owned.sol";
import "Certifier.sol";
import "Token.sol";

interface Recorder {
	function received(address _who, uint _value);
	function done();
}

// BasicCoin, ECR20 tokens that all belong to the owner for sending around
contract BasicToken is Token {
	// STRUCTS

	// An account; has a balance and an allowance.
	struct Account {
		uint balance;
		mapping (address => uint) allowanceOf;
	}

	// FIELDS
	// (STATE)

	// All accounts.
	mapping (address => Account) accounts;

	// The total number of tokens.
	uint public totalSupply = 0;

	// MODIFIERS

	// Throws unless `_owner` owns some `_amount` of tokens.
	modifier when_owns(address _owner, uint _amount) {
		if (accounts[_owner].balance < _amount) throw;
		_;
	}

	// Throws unless `_spender` is permitted to transfer `_amount` from the
	// account of `_owner`.
	modifier when_has_allowance(address _owner, address _spender, uint _amount) {
		if (accounts[_owner].allowanceOf[_spender] < _amount) throw;
		_;
	}

	// FUNCTIONS

	// Disable the fallback function.
	function() { throw; }

	// (CONSTANT)

	// Return the balance of a specific address.
	function balanceOf(address _who)
		constant
		returns (uint256)
	{
		return accounts[_who].balance;
	}

	// Return the delegated allowance available to spend.
	function allowance(address _owner, address _spender)
		constant
		returns (uint256)
	{
		return accounts[_owner].allowanceOf[_spender];
	}

	// (MUTATING)

	// Transfer tokens between accounts.
	function transfer(address _to, uint256 _value)
		when_owns(msg.sender, _value)
		returns (bool)
	{
		accounts[msg.sender].balance -= _value;
		accounts[_to].balance += _value;

		Transfer(msg.sender, _to, _value);
		return true;
	}

	// Transfer tokens from a delegated account.
	function transferFrom(address _from, address _to, uint256 _value)
		when_owns(_from, _value)
		when_has_allowance(_from, msg.sender, _value)
		returns (bool)
	{
		accounts[_from].allowanceOf[msg.sender] -= _value;
		accounts[_from].balance -= _value;
		accounts[_to].balance += _value;

		Transfer(_from, _to, _value);
		return true;
	}

	// Approve an amount for a delegate to transfer.
	function approve(address _spender, uint256 _value)
		returns (bool)
	{
		accounts[msg.sender].allowanceOf[_spender] += _value;

		Approval(msg.sender, _spender, _value);
		return true;
	}
}

contract BasicMintableToken is BasicToken {

	// The address of the account which is allowed to mint tokens.
	address minter;

	// Only continue if the sender is the minter.
	modifier only_minter { if (msg.sender != minter) throw; _; }

	// Tokens have been minted.
	event Minted(address indexed who, uint value);

	// Create the contract, setting the minting account.
	function BasicMintableToken(address _minter) {
		minter = _minter;
	}

	function setMinter(address _minter) only_minter {
		minter = _minter;
	}

	// Credit `_value` tokens to `_who`.
	function mint(address _who, uint _value) only_minter {
		accounts[_who].balance += _value;
		totalSupply += _value;
		Minted(_who, _value);
	}
}

contract EndableMintableToken is BasicToken {

	// The address of the account which is allowed to mint tokens.
	address minter;

	// Only continue if the sender is the minter.
	modifier only_minter { if (msg.sender != minter) throw; _; }

	// Only continue if minting has ceased.
	modifier when_transferable { if (minter != 0) throw; _; }

	// Tokens have been minted.
	event Minted(address indexed who, uint value);

	// Create the contract, setting the minting account.
	function EndableMintableToken(address _minter) {
		minter = _minter;
	}

	// Cease all minting activities and make the tokens transferable.
	//
	// This cannot be reversed.
	function ceaseMinting() only_minter {
		minter = 0;
	}

	// Credit `_value` tokens to `_who`.
	function mint(address _who, uint _value) only_minter {
		accounts[_who].balance += _value;
		totalSupply += _value;
		Minted(_who, _value);
	}

	// Transfer tokens between accounts.
	function transfer(address _to, uint256 _value)
		when_transferable
		returns (bool)
	{
		return super.transfer(_to, _value);
	}

	// Transfer tokens from a delegated account.
	function transferFrom(address _from, address _to, uint256 _value)
		when_transferable
		returns (bool)
	{
		return super.transferFrom(_from, _to, _value);
	}
}

contract ThawableMintableToken is EndableMintableToken {

	// Unix time when frozen tokens may be thawed.
	uint iceAgeEnds;

	mapping (address => uint) public frozenBalanceOf;

	// Only if we're out of the ice age.
	modifier only_when_thawable { if (now < iceAgeEnds) throw; _; }

	// Tokens have been minted.
	event MintedFrozen(address indexed who, uint value);

	// Tokens have been minted.
	event Thawed(address indexed who, uint value);

	// Create the contract, setting the minting account.
	function ThawableMintableToken(uint _iceAgeEnds) {
		iceAgeEnds = _iceAgeEnds;
	}

	// Credit `_value` frozen tokens to `_who`.
	function mintFrozen(address _who, uint _value) only_minter {
		frozenBalanceOf[_who] += _value;
		totalSupply += _value;
		MintedFrozen(_who, _value);
	}

	// Converts all of the sender's frozen tokens into normal tokens if we're
	// out of the ice age.
	function thaw() only_when_thawable {
		Thawed(msg.sender, frozenBalanceOf[msg.sender]);
		accounts[msg.sender].balance += frozenBalanceOf[msg.sender];
		frozenBalanceOf[msg.sender] = 0;
	}
}

contract BasicMintableReceiverToken is ThawableMintableToken, Recorder {
	function received(address _who, uint _value) { super.mint(_who, _value); }
	function done() { super.ceaseMinting(); }
}

/// Will accept Ether "contributions" and record each both as a log and in a
/// queryable record.
contract Receipter {
	/// Constructor. `_admin` has the ability to pause the
	/// contribution period and, eventually, kill this contract. `_treasury`
	/// receives all funds. `_beginTime` and `_endTime` define the begin and
	/// end of the period.
    function Receipter(address _recorder, address _admin, address _treasury, uint _beginTime, uint _endTime) {
		recorder = Recorder(_recorder);
        admin = _admin;
        treasury = _treasury;
        beginTime = _beginTime;
        endTime = _endTime;
    }

	// Can only be called by _admin.
    modifier only_admin { if (msg.sender != admin) throw; _; }
	// Can only be called by prior to the period.
    modifier only_before_period { if (now >= beginTime) throw; _; }
	// Only does something if during the period.
    modifier when_during_period { if (now >= beginTime && now < endTime && !isHalted) _; }
	// Can only be called during the period when not halted.
    modifier only_during_period { if (now < beginTime || now >= endTime || isHalted) throw; _; }
	// Can only be called during the period when halted.
    modifier only_during_halted_period { if (now < beginTime || now >= endTime || !isHalted) throw; _; }
	// Can only be called after the period.
    modifier only_after_period { if (now < endTime || isHalted) throw; _; }
	// The value of the message must be sufficiently large to not be considered dust.
    modifier is_not_dust { if (msg.value < dust) throw; _; }

	/// Some contribution `amount` received from `recipient`.
    event Received(address indexed recipient, uint amount);
	/// Period halted abnormally.
    event Halted();
	/// Period restarted after abnormal halt.
    event Unhalted();

	/// Fallback function: receive a contribution from sender.
    function() payable {
        processReceipt(msg.sender);
    }

	/// Receive a contribution from sender.
	function receive() payable returns (bool) {
        return processReceipt(msg.sender);
    }

	/// Receive a contribution from `_recipient`.
    function receiveFrom(address _recipient) payable returns (bool) {
		return processReceipt(_recipient);
    }

	/// Receive a contribution from `_recipient`.
    function processReceipt(address _recipient)
		only_during_period
		is_not_dust
		internal
		returns (bool)
	{
        if (!treasury.call.value(msg.value)()) throw;
        recorder.received(_recipient, msg.value);
        total += msg.value;
        Received(_recipient, msg.value);
		return true;
    }

	/// Halt the contribution period. Any attempt at contributing will fail.
    function halt() only_admin only_during_period {
        isHalted = true;
        Halted();
    }

	/// Unhalt the contribution period.
    function unhalt() only_admin only_during_halted_period {
        isHalted = false;
        Unhalted();
    }

	/// Kill this contract.
    function kill() only_admin only_after_period {
		recorder.done();
        suicide(treasury);
    }

	// How much is enough?
    uint public constant dust = 100 finney;

	// The contract which gets called whenever anything is received.
	Recorder public recorder;
	// Who can halt/unhalt/kill?
    address public admin;
	// Who gets the stash?
    address public treasury;
	// When does the contribution period begin?
    uint public beginTime;
	// When does the period end?
    uint public endTime;

	// Are contributions abnormally halted?
    bool public isHalted = false;

    mapping (address => uint) public record;
    uint public total = 0;
}

contract SignedReceipter is Receipter {
    function SignedReceipter(address _recorder, address _admin, address _treasury, uint _beginTime, uint _endTime, bytes32 _sigHash) {
		recorder = Recorder(_recorder);
        admin = _admin;
        treasury = _treasury;
        beginTime = _beginTime;
        endTime = _endTime;
        sigHash = _sigHash;
    }

    modifier only_signed(address who, uint8 v, bytes32 r, bytes32 s) { if (ecrecover(sigHash, v, r, s) != who) throw; _; }

    function() payable { throw; }
	function receive() payable returns (bool) { throw; }
	function receiveFrom(address) payable returns (bool) { throw; }

    /// Fallback function: receive a contribution from sender.
    function receiveSigned(uint8 v, bytes32 r, bytes32 s) payable returns (bool) {
        return processSignedReceipt(msg.sender, v, r, s);
    }

	/// Receive a contribution from `_recipient`.
    function receiveSignedFrom(address _sender, uint8 v, bytes32 r, bytes32 s) payable returns (bool) {
		return processSignedReceipt(_sender, v, r, s);
    }

	/// Receive a contribution from `_recipient`.
    function processSignedReceipt(address _sender, uint8 v, bytes32 r, bytes32 s)
		only_signed(_sender, v, r, s)
		internal
		returns (bool)
	{
		return processReceipt(_sender);
    }

    bytes32 sigHash;
}

contract CertifyingReceipter is SignedReceipter {
    function CertifyingReceipter(address _recorder, address _admin, address _treasury, uint _beginTime, uint _endTime, bytes32 _sigHash, address _certifier) {
		recorder = Recorder(_recorder);
		admin = _admin;
        treasury = _treasury;
        beginTime = _beginTime;
        endTime = _endTime;
        sigHash = _sigHash;
        certifier = Certifier(_certifier);
    }

	/// Fallback function: receive a contribution from sender.
    function receiveSigned(uint8 v, bytes32 r, bytes32 s) payable returns (bool) {
        return processCertifiedReceipt(msg.sender, v, r, s);
    }

	function receiveSignedFrom() payable returns (bool) { throw; }

	function processCertifiedReceipt(address _sender, uint8 v, bytes32 r, bytes32 s)
        internal
        only_certified(msg.sender)
		returns (bool)
    {
		return processSignedReceipt(_sender, v, r, s);
    }

    modifier only_certified(address who) { if (!certifier.certified(who)) throw; _; }

    Certifier certifier;
}

contract FairReceipter is CertifyingReceipter {
    function FairReceipter(
		address _recorder,
		address _admin,
		address _treasury,
		uint _beginTime,
		uint _endTime,
		bytes32 _sigHash,
		address _certifier,
		uint _cap,
		uint _segmentDuration
	) {
		recorder = Recorder(_recorder);
		admin = _admin;
        treasury = _treasury;
		beginTime = _beginTime;
        endTime = _endTime;
		sigHash = _sigHash;
        certifier = Certifier(_certifier);
		cap = _cap;
		segmentDuration = _segmentDuration;
    }

    function receive(uint8 v, bytes32 r, bytes32 s)
		only_under_max(msg.sender)
        payable
		returns (bool)
    {
		return processCertifiedReceipt(msg.sender, v, r, s);
    }

	function maxBuy() when_during_period public returns (uint) {
        uint segment = (now - beginTime) / segmentDuration;
		// actually just: segment = min(segment, endSegment);
        if (segment > endSegment)
            segment = endSegment;
        return firstMaxBuy << segment;
    }

	function maxBuyFor(address _who) when_during_period public returns (uint) {
        var segmentMaxBuy = maxBuy();
		// Should never happen, but just in case...
        if (record[_who] >= segmentMaxBuy)
            return 0;
        return segmentMaxBuy - record[_who];
    }

	modifier only_under_max(address who) { if (msg.value > maxBuyFor(who)) throw; _; }

    uint constant firstMaxBuy = 1 ether;
    uint constant endSegment = 16;

    uint segmentDuration;
    uint cap;
}
