//sol CoreVeto
// Asymmetric, dual-sig wallet.
// @authors:
// Gav Wood <gavin@parity.io>
// Two predefined and constant accounts are symbiotic; owner may submit transactions for
// execution and some pre-defined period later, may have them be executed.
// Within this period either of the two accounts may cancel the request for
// some predefined (anti-griefing) value to be paid.
// Designed to be used with other, more complex, account access infrastructure
// as a final fail-safe mechanism to ensure the chances of outright theft are
// minimised.
// Currently there is no functionality to alter the identities of these two
// accounts, mainly to reduce complexity and ensure the logic is bug-free.


contract creator {
	function doCreate(uint _value, bytes _code) internal returns (address o_addr) {
	    bool failed;
		assembly {
			o_addr := create(_value, add(_code, 0x20), mload(_code))
			failed := iszero(extcodesize(o_addr))
		}
		require(!failed);
	}
}

 contract CoreVeto is creator {
	// Funds has arrived into the wallet (record how much).
	event Deposit(address _from, uint value);
	// Single transaction going out of the wallet (record who signed for it, how much, and to whom it's going).
	event Executed(uint value, address to, bytes data, address created);
	event Requested(bytes32 txHash);
	event Vetoed(address who, bytes32 txHash);

	function CoreVeto(address _owner, address _veto, uint _vetoPayment, uint _vetoPeriod) {
		owner = _owner;
		veto = _veto;
		vetoPayment = _vetoPayment;
		vetoPeriod = _vetoPeriod;
	}

	function permit(bytes32 _txHash) only_owner {
		Requested(_txHash);
		requests[_txHash] = now + vetoPeriod;
		lastRequest = _txHash;
	}

	function execute(address _to, uint _value, bytes _data)
		only_permitted(sha3(msg.data))
	{
		address created = 0;
		if (_to == address(0)) {
			created = doCreate(_value, _code);
		} else {
			require(_to.call.value(_value)(_data));
		}
		delete requests[sha3(msg.data)];
		Executed(_value, _to, _data, created);
	}

	function veto(bytes32 _txHash) payable only_vetoer only_paid {
		delete requests[_txHash];
		Vetoed(msg.sender, _txHash);
	}

	function () payable {
		Deposit(msg.sender, msg.value);
	}

	modifier only_permitted(bytes32 txHash) { require(requests[txHash] != 0 && now > requests[txHash]); _; }
	modifier only_vetoer { require(msg.sender == veto || msg.sender == owner); _; }
	modifier only_owner { require(msg.sender == owner); _; }
	modifier only_paid { require(msg.value >= vetoPayment); _; }

	// Constants
	address public owner;
	address public veto;
	uint public vetoPayment;
	uint public vetoPeriod;

	// State
	mapping (bytes32 => uint) public requests;
	bytes32 public lastRequest;
}
