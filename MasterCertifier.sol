//! A master certifier contract, taken from ethcore/sms-verification.
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

pragma solidity ^0.4.13;

import "Owned.sol";
import "Certifier.sol";

contract MasterCertifier is Owned {
	function addCertifier(Certifier _who) public only_owner {
        require (_who != Certifier(0));
		certifiers.push(_who);
	}

	function removeCertifier(Certifier _who) public only_owner returns (bool) {
		for (uint i = 0; i < certifiers.length; ++i) {
			if (certifiers[i] == _who) {
                uint lastIndex = certifiers.length - 1;
                certifiers[i] = certifiers[lastIndex];
                delete certifiers[lastIndex];
                certifiers.length = lastIndex;
				return true;
			}
		}
		return false;
	}

	function certified(address _who) public constant returns (bool) {
		for (uint i = 0; i < certifiers.length; ++i) {
			if (certifiers[i].certified(_who)) {
				return true;
			}
		}
		return false;
	}
	function getData(address _who, string _field) public constant returns (bytes32) {
		for (uint i = 0; i < certifiers.length; ++i) {
			if (certifiers[i].certified(_who)) {
				return certifiers[i].getData(_who, _field);
			}
		}
	}
	function getAddress(address _who, string _field) public constant returns (address) {
		for (uint i = 0; i < certifiers.length; ++i) {
			if (certifiers[i].certified(_who)) {
				return certifiers[i].getAddress(_who, _field);
			}
		}
	}
	function getUint(address _who, string _field) public constant returns (uint) {
		for (uint i = 0; i < certifiers.length; ++i) {
			if (certifiers[i].certified(_who)) {
				return certifiers[i].getUint(_who, _field);
			}
		}
	}

	Certifier[] public certifiers;
}
