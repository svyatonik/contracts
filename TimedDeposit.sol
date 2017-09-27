//! Timed deposit contract.
//! By Gavin Wood, 2017.
//! Released under the Apache Licence 2.

/// Simply deposit contract. Effectively a single-use 1 of 2, except that one
/// (the sender) cannot access the funds until after 6 months.
contract TimedDeposit {
	function TimedDeposit(address _sender, address _receiver) {
		sender = _sender;
		receiver = _receiver;
	}

	function () { throw; }

	function refund() public {
		require(msg.sender == sender);
		require(now > expiry);
		this.suicide(sender);
	}

	function take() public {
		require(msg.sender == receiver);
		this.suicide(receiver);
	}

	address public sender;
	address public receiver;
	uint constant public expiry = now + 6 months;
}
