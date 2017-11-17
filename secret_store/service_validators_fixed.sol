pragma solidity ^0.4.18;

/// Authorities-owned contract.
contract AuthoritiesOwned {
	/// Only pass when called by authority.
	modifier onlyAuthority { require (isAuthority(msg.sender)); _; }

	/// Confirmations from authorities.
	struct Confirmations {
		uint threshold;
		mapping (address => bytes32) confirmations;
		address[] confirmedAutorities;
	}

	/// Constructor.
	function AuthoritiesOwned() internal {
		authorities.push(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
	}

	/// Drain contract, paying equal amount to ech of authorities.
	function drain() public onlyAuthority {
		var authorities = getValidatorsInternal();
		var balance = this.balance;
		var authorityShare = balance / authorities.length;
		for (uint i = 0; i < authorities.length - 1; i++) {
			authorities[i].transfer(authorityShare);
			balance = balance - authorityShare;
		}
		authorities[authorities.length - 1].transfer(balance);
	}

	/// Is authority?
	function isAuthority(address authority) internal view returns (bool) {
		var authorities = getValidatorsInternal();
		for (uint i = 0; i < authorities.length; i++) {
			if (authority == authorities[i]) {
				return true;
			}
		}
		return false;
	}

	/// Get validators list.
	function getValidatorsInternal() view internal returns (address[]) {
		return authorities;
	}

	/// Recover authority address from signature.
	function recoverAuthority(bytes32 hash, uint8 v, bytes32 r, bytes32 s) view internal returns (address) {
		var authority = ecrecover(hash, v, r, s);
		require(isAuthority(authority));
		return authority;
	}

	/// Check that we have enough confirmations from authorities.
	function insertConfirmation(Confirmations storage confirmations, address authority, bytes32 confirmation) internal returns (bool) {
		// check if haven't confirmed before
		if (confirmations.confirmations[authority] != bytes32(0)) {
			return false;
		}
		confirmations.confirmations[authority] = confirmation;
		confirmations.confirmedAutorities.push(authority);

		// calculate number of nodes that have reported the same confirmation
		uint confirmationsCount = 1;
		if (confirmationsCount < confirmations.threshold + 1) {
			// skip last (new) authority, because we have already counted it in confirmationsCount
			for (uint i = 0; i < confirmations.confirmedAutorities.length - 1; ++i) {
				if (confirmations.confirmations[confirmations.confirmedAutorities[i]] == confirmation) {
					confirmationsCount = confirmationsCount + 1;
				}
			}
		}

		return confirmationsCount >= confirmations.threshold + 1;
	}

	/// Clear internal confirmations mappings.
	function clearConfirmations(Confirmations storage confirmations) internal {
		for (uint i = 0; i < confirmations.confirmedAutorities.length; ++i) {
			delete confirmations.confirmations[confirmations.confirmedAutorities[i]];
		}
	}

	/// Authorities.
	address[] authorities;
}

/// Server key generation contract. This contract allows to generate SecretStore KeyPairs, which
/// could be used later to sign messages.
contract ServerKeyGenerator is AuthoritiesOwned {
	/// Only pass when fee is paid.
	modifier whenServerKeyGenerationFeePaid { require (msg.value >= serverKeyGenerationFee); _; }
	/// Only pass when 'correct' public is passed.
	modifier validPublicKey(bytes publicKey) { require(publicKey.length == 64); _; }

	/// Generation request.
	struct ServerKeyGenerationRequest {
		bool isActive;
		Confirmations confirmations;
	}

	/// When sever key generation request is received.
	event ServerKeyRequested(bytes32 indexed serverKeyId, uint indexed threshold);
	/// When server key is generated.
	event ServerKeyGenerated(bytes32 indexed serverKeyId, bytes serverKeyPublic);

	/// Request new server key generation.
	/// requester_public must be unique public key (only one key can be generated for given public).
	/// Generated key will be published via ServerKeyGenerated event when available.
	function generateServerKey(bytes32 serverKeyId, uint threshold) public payable whenServerKeyGenerationFeePaid {
		var request = serverKeyGenerationRequests[serverKeyId];
		require(!request.isActive);
		request.isActive = true;
		request.confirmations.threshold = threshold;
		ServerKeyRequested(serverKeyId, threshold);
	}

	/// Called when generation is reported by one of key authorities.
	function serverKeyGenerated(bytes32 serverKeyId, bytes serverKeyPublic, uint8 v, bytes32 r, bytes32 s) public validPublicKey(serverKeyPublic) {
		// check if request still active
		var request = serverKeyGenerationRequests[serverKeyId];
		if (!request.isActive) {
			return;
		}

		// insert confirmation && check if there are enough confirmations
		var authority = recoverAuthority(keccak256(serverKeyPublic), v, r, s);
		if (!insertConfirmation(request.confirmations, authority, keccak256(serverKeyPublic))) {
			return;
		}

		// clear confirmations
		clearConfirmations(request.confirmations);
		delete serverKeyGenerationRequests[serverKeyId];

		// ...and finally fire event
		ServerKeyGenerated(serverKeyId, serverKeyPublic);
	}

	/// Server key generation fee. TODO: change to actual value
	uint public serverKeyGenerationFee = 1 finney;

	/// Pending generation requests.
	mapping (bytes32 => ServerKeyGenerationRequest) serverKeyGenerationRequests;
}

/// Secret store service contract.
contract SecretStoreService is ServerKeyGenerator {
}
