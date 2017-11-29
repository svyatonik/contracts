//! The E-mail verification contract.
//!
//! Copyright 2016 Gavin Wood, Parity Technologies Ltd.
//!
//! Licensed under the Apache License, Version 2.0 (the "License");
//! you may not use this file except in compliance with the License.
//! You may obtain a copy of the License at
//!
//!     http://www.apache.org/licenses/LICENSE-2.0
//!
//! Unless required by applicable law or agreed to in writing, software
//! distributed under the License is distributed on an "AS IS" BASIS,
//! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//! See the License for the specific language governing permissions and
//! limitations under the License.

pragma solidity ^0.4.0;

import "Owned.sol";

// From Registry.sol
contract ReverseRegistry {
	event ReverseConfirmed(string indexed name, address indexed reverse);
	event ReverseRemoved(string indexed name, address indexed reverse);

	function hasReverse(bytes32 _name) constant returns (bool);
	function getReverse(bytes32 _name) constant returns (address);
	function canReverse(address _data) constant returns (bool) {}
	function reverse(address _data) constant returns (string) {}
}

// From Certifier.sol
contract Certifier {
	event Confirmed(address indexed reverse);
	event Revoked(address indexed reverse);

	function certified(address _who) constant returns (bool);
	function lookup(address _who, string _field) constant returns (string) {}
	function lookupHash(address _who, string _field) constant returns (bytes32);
}

contract ProofOfEmail is Owned, Certifier, ReverseRegistry {
	// Events.
	event Requested(address indexed who, bytes32 indexed emailHash);
	event Puzzled(address indexed who, bytes32 indexed emailHash, bytes32 puzzle);

	// ReverseRegistry API -> We map the namespace of SHA3(e-mail address)s to a 'reverse' and 'A' address. We can't do the full
	// reverse or issue events, since we don't have the plaintext email.
	function getAddress(bytes32 _name, string _key) constant returns (address) { return entries[_name]; }
	function hasReverse(bytes32 _name) constant returns (bool) { return entries[_name] != 0; }
	function getReverse(bytes32 _name) constant returns (address) { return entries[_name]; }

	// Certifier API -> If an address has an associate e-mail, then it is considered certified. We cannot lookup the data
	// itself since we store only the hash.
	function certified(address _who) constant returns (bool) { return reverseHash[_who] != 0; }
	function lookupHash(address _who, string _field) constant returns (bytes32) { return reverseHash[_who]; }

	// Puzzle/confirmation functions.
	function request(bytes32 _emailHash) payable when_fee_paid {
		Requested(msg.sender, _emailHash);
	}
	function puzzle(address _who, bytes32 _puzzle, bytes32 _emailHash) only_owner {
		puzzles[_puzzle] = _emailHash;
		Puzzled(_who, _emailHash, _puzzle);
	}
	function confirm(bytes32 _code) returns (bool) {
		var emailHash = puzzles[sha3(_code)];
		if (emailHash == 0)
			return;
		delete puzzles[sha3(_code)];
		if (entries[emailHash] != 0 || reverseHash[msg.sender] != 0)
			return;
		entries[emailHash] = msg.sender;
		reverseHash[msg.sender] = emailHash;
		Confirmed(msg.sender);
		return true;
	}

	// Admin functions for the owner.
	function setFee(uint _new) only_owner {
		fee = _new;
	}
	function drain() only_owner {
		if (!msg.sender.send(this.balance))
			throw;
	}

	// Modifiers.
	modifier when_fee_paid { if (msg.value < fee) return; _; }

	// Fields.
	mapping (bytes32 => address) entries;
	mapping (address => bytes32) reverseHash;

	uint public fee = 0 finney;
	mapping (bytes32 => bytes32) puzzles;
}
