//! The SMS-verification contract
//!
//! Copyright 2017 Gavin Wood, Parity Technologies Ltd.
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

pragma solidity ^0.4.17;

import "Owned.sol";
import "Certifier.sol";

contract SimpleCertifier is Owned, Certifier {
	modifier only_delegate {
        require(msg.sender == delegate); _;
    }
	modifier only_certified(address _who) {
        require(certs[_who].active); _;
    }

	struct Certification {
		bool active;
		mapping (string => bytes32) meta;
	}

	function certify(address _who) only_delegate public {
		certs[_who].active = true;
		Confirmed(_who);
	}
	function revoke(address _who) only_delegate only_certified(_who) public {
		certs[_who].active = false;
		Revoked(_who);
	}
	function certified(address _who) constant public returns (bool) { return certs[_who].active; }
	function get(address _who, string _field) constant public returns (bytes32) { return certs[_who].meta[_field]; }
	function getAddress(address _who, string _field) constant public returns (address) { return address(certs[_who].meta[_field]); }
	function getUint(address _who, string _field) constant public returns (uint) { return uint(certs[_who].meta[_field]); }
	function setDelegate(address _new) only_owner public { delegate = _new; }

	mapping (address => Certification) certs;
	// So that the server posting puzzles doesn't have access to the ETH.
	address public delegate = msg.sender;
}



contract ProofOfSMS is SimpleCertifier {

	modifier when_fee_paid { require (msg.value >= fee); _; }

	event Requested(address indexed who);
	event Puzzled(address indexed who, bytes32 puzzle);

	function request() payable when_fee_paid public {
		require (!certs[msg.sender].active);
		Requested(msg.sender);
	}

	function puzzle(address _who, bytes32 _puzzle) only_delegate public {
		puzzles[_who] = _puzzle;
		Puzzled(_who, _puzzle);
	}

	function confirm(bytes32 _code) public returns (bool) {
		if (puzzles[msg.sender] != keccak256(_code))
			return;
		delete puzzles[msg.sender];
		certs[msg.sender].active = true;
		Confirmed(msg.sender);
		return true;
	}

	function setFee(uint _new) only_owner public {
		fee = _new;
	}

	function drain() only_owner public {
		msg.sender.transfer(this.balance);
	}

	function certified(address _who) constant public returns (bool) {
		return certs[_who].active;
	}

	mapping (address => bytes32) puzzles;

	uint public fee = 30 finney;
}
