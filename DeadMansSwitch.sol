// DeadMansSwitch contract, by Gavin Wood.
// Copyright Parity Technologies Ltd (UK), 2016.
// This code may be distributed under the terms of the Apache Licence, version 2
// or the MIT Licence, at your choice.

pragma solidity ^0.4;

/// This is intended to be used as a basic wallet. It provides the Received event
/// in order to track incoming transactions. It also has one piece of additional
/// functionality: to nominate a backup owner which can, after a timeout period,
/// claim ownership over the account.
contract DeadMansSwitch {
	event ReclaimBegun();
	event Reclaimed();
	event Sent(address indexed to, uint value, bytes data);
	event Received(address indexed from, uint value, bytes data);
	event Reset();
	event OwnerChanged(address indexed old, address indexed now);
	event BackupChanged(address indexed old, address indexed now);
	event ReclaimPeriodChanged(uint old, uint now);

	function DeadMansSwitch(address _owner, address _backup, uint _reclaimPeriod) public {
		owner = _owner;
		backup = _backup;
		reclaimPeriod = _reclaimPeriod;
	}

	function() payable public { Received(msg.sender, msg.value, msg.data); }

	// Backup functions

	function beginReclaim() only_backup when_no_timeout public {
		timeout = now + reclaimPeriod;
		ReclaimBegun();
	}

	function finalizeReclaim() only_backup when_timed_out public {
		owner = backup;
		timeout = 0;
		Reclaimed();
	}

	function reset() only_owner_or_backup public {
		timeout = 0;
		Reset();
	}

	// Owner functions

	function send(address _to, uint _value, bytes _data) only_owner public {
		require(_to.call.value(_value)(_data));
		Sent(_to, _value, _data);
	}

	function setOwner(address _owner) only_owner public {
		OwnerChanged(owner, _owner);
		owner = _owner;
	}

	function setBackup(address _backup) only_owner public {
		BackupChanged(backup, _backup);
		backup = _backup;
	}

	function setReclaimPeriod(uint _period) only_owner public {
		ReclaimPeriodChanged(reclaimPeriod, _period);
		reclaimPeriod = _period;
	}

	// Inspectors

	function reclaimStarted() constant public returns (bool) {
		return timeout != 0;
	}

	function canFinalize() constant public returns (bool) {
		return timeout != 0 && now > timeout;
	}

	function timeLeft() constant only_when_timeout public returns (uint) {
		return now > timeout ? 0 : timeout - now;
	}

	modifier only_owner { require (msg.sender == owner); _; }
	modifier only_backup { require (msg.sender == backup); _; }
	modifier only_owner_or_backup { require (msg.sender == backup || msg.sender == owner); _; }
	modifier only_when_timeout { require (timeout != 0); _; }
	modifier when_no_timeout { if (timeout == 0) _; }
	modifier when_timed_out { if (timeout != 0 && now > timeout) _; }

	address public owner;
	address public backup;
	uint public reclaimPeriod;
	uint public timeout;
}
