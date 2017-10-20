//! Certifier contract, taken from ethcore/sms-verification
//! By Gav Wood (Ethcore), 2016.
//! Released under the Apache Licence 2.

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
