//! The Dutch-Buying contract.
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

pragma solidity ^0.4.7;

/// Will accept Ether "contributions" and record each both as a log and in a
/// queryable record.
contract Receipter {
	/// Constructor. `_admin` has the ability to pause the
	/// contribution period and, eventually, kill this contract. `_treasury`
	/// receives all funds. `_beginBlock` and `_endBlock` define the begin and
	/// end of the period.
    function Receipter(address _admin, address _treasury, uint _beginBlock, uint _endBlock) {
        admin = _admin;
        treasury = _treasury;
        beginBlock = _beginBlock;
        endBlock = _endBlock;
    }

	// Can only be called by _admin.
    modifier only_admin { if (msg.sender != admin) throw; _; }
	// Can only be called by prior to the period.
    modifier only_before_period { if (block.number >= beginBlock) throw; _; }
	// Can only be called during the period when not halted.
    modifier only_during_period { if (block.number < beginBlock || block.number >= endBlock || isHalted) throw; _; }
	// Can only be called during the period when halted.
    modifier only_during_halted_period { if (block.number < beginBlock || block.number >= endBlock || !isHalted) throw; _; }
	// Can only be called after the period.
    modifier only_after_period { if (block.number < endBlock || isHalted) throw; _; }
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
        receiveFrom(msg.sender);
    }

	/// Receive a contribution from `_recipient`.
    function receiveFrom(address _recipient) payable only_during_period is_not_dust {
        if (!treasury.call.value(msg.value)()) throw;
        record[_recipient] += msg.value;
        total += msg.value;
        Received(_recipient, msg.value);
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
        suicide(treasury);
    }

	// How much is enough?
    uint public constant dust = 100 finney;

	// Who can halt/unhalt/kill?
    address public admin;
	// Who gets the stash?
    address public treasury;
	// When does the contribution period begin?
    uint public beginBlock;
	// When does the period end?
    uint public endBlock;

	// Are contributions abnormally halted?
    bool public isHalted = false;

    mapping (address => uint) public record;
    uint public total = 0;
}

contract Recorder {
	function received(address _who, uint _value);
	function done();
}

contract DutchBuyin {
	event Bid(address indexed who, uint maxUnitPrice, uint value, uint accumulatedValue);
	event InjectedBid(address indexed who, uint value);
	event Ended();
	event StrikeFound(uint price, uint tokens, uint tieBreakTime);
	event Sold(address indexed who, uint tokens, uint refund);
	event Refunded(address indexed who, uint refund);

	modifier is_non_zero(uint v) { if (v == 0) throw; _; }
	modifier value_at_least(uint v) { if (msg.value < v) throw; _; }

	modifier auction_in_progress { if (now < begin || ended || tiePhaseBegin != 0) throw; _; }
	modifier strike_in_progress { if (!ended || tiePhaseBegin != 0) throw; _; }
	modifier when_have_strike_price { if (tiePhaseBegin == 0) throw; _; }

	modifier when_has_receipt(address _who) { if (receipts[_who].price == 0) throw; _; }
	modifier sensible_price(uint _price) { if (_price < MINIMUM_STRIKE) throw; _; }

	modifier only_owner { if (msg.sender != owner) throw; _; }

	// Assumes when_have_strike_price, ensures the sender either placed a
	// strictly higher bid to the strike price or that the time is 24 hours
	// after the strike price is found.
	modifier when_in_acceptable_phase(address _who) { if (receipts[_who].price == strike && now <= tiePhaseBegin) throw; _; }

	function auctioning() constant returns (bool) { return now > begin && !ended && tiePhaseBegin == 0; }
	function findingStrike() constant returns (bool) { return ended && tiePhaseBegin == 0; }
	function foundStrike() constant returns (bool) { return tiePhaseBegin != 0; }

	function prepBid(uint _maxUnitPrice)
		constant
		returns (uint o_nextHighestPrice, uint o_nextHighestOnOldPrice)
	{
		o_nextHighestPrice = highestPrice;
		while (prices[o_nextHighestPrice].nextLowerPrice > _maxUnitPrice) {
			o_nextHighestPrice = prices[o_nextHighestPrice].nextLowerPrice;
		}
		o_nextHighestOnOldPrice = highestPrice;
		while (prices[o_nextHighestPrice].nextLowerPrice > receipts[msg.sender].price) {
			o_nextHighestPrice = prices[o_nextHighestPrice].nextLowerPrice;
		}
	}

	function currentStrikePrice()
		constant
		returns (uint strike)
	{
		strike = highestPrice;
		uint t = 0;
		while (strike > 0) {
			t += prices[strike].totalValue;
			uint p = prices[strike].nextLowerPrice;
			if (p == 0 || t / strike >= TOTAL_MINTABLE) {
				return;
			}
			strike = p;
		}
	}

	function bid(uint _maxUnitPrice, uint _nextHighestPrice, uint _nextHighestOnOldPrice)
		payable
		auction_in_progress
		is_non_zero(_maxUnitPrice)
		sensible_price(_maxUnitPrice)
	{
		introduceBid(msg.sender, msg.value, _maxUnitPrice, _nextHighestPrice, _nextHighestOnOldPrice);
		Bid(msg.sender, receipts[msg.sender].price, msg.value, receipts[msg.sender].value);
		checkEnd();
	}

	// Injects a super-high bid of `_value` on behalf of `_who`.
	function inject(address _who, uint _value) only_owner {
		introduceBid(_who, _value, MAXIMUM_STRIKE, 0, 0);
		InjectedBid(_who, _value);
	}

	function() payable auction_in_progress {
		introduceBid(msg.sender, msg.value, MAXIMUM_STRIKE, 0, 0);
		Bid(msg.sender, receipts[msg.sender].price, msg.value, receipts[msg.sender].value);
		checkEnd();
	}

	function progressStrike() strike_in_progress {
		strike = highestPrice;
		totalValue += prices[highestPrice].totalValue;

		uint tokens = totalValue / strike;
		if (tokens >= TOTAL_MINTABLE) {
			tiePhaseBegin = now + TIE_PHASE_DURATION;
			StrikeFound(strike, tokens, tiePhaseBegin);
		}

		deleteHighestShelf();
	}

	/// Finalise for the sender's bid.
	function finalise() { finaliseFor(msg.sender); }

	/// Finalise for `_who`'s bid. Will either return their cash or mint tokens.
	function finaliseFor(address _who)
		when_have_strike_price
		when_has_receipt(_who)
		when_in_acceptable_phase(_who)
	{
		deleteHighestShelf();
		uint refund = receipts[_who].value;
		if (receipts[_who].price >= strike) {
			uint tokens = receipts[_who].value / strike;
			if (tokens + totalMinted > TOTAL_MINTABLE) {
				tokens = TOTAL_MINTABLE - totalMinted;
			}
			refund -= tokens * strike;
			tokenRecorder.received(_who, tokens);
			Sold(_who, tokens, refund);
		} else {
			Refunded(_who, refund);
		}
		delete receipts[_who];
		if (refund > 0) {
			if (!_who.call.value(refund)()) throw;
		}
	}

	function checkEnd() {
		if (now > beginEnd && uint(block.blockhash(block.number - 2) ^ block.blockhash(block.number - 1)) % END_BLOCK_MAX_DURATION + (now - beginEnd) > END_BLOCK_MAX_DURATION - 1) {
			ended = true;
			Ended();
		}
	}

	function introduceBid(
		address _who,
		uint _value,
		uint _maxUnitPrice,
		uint _nextHighestPrice,
		uint _nextHighestOnOldPrice
	)
		internal
	{
		uint totalBidValue = _value;
		uint oldPrice = receipts[_who].price;
		// bidder may only raise their bid.
		if (oldPrice > _maxUnitPrice) throw;
		// if the old bid is same the same price shelf as this...
		if (oldPrice == _maxUnitPrice) {
			// ...then short cut, because it's easy:
			receipts[_who].value += _value;
			prices[oldPrice].totalValue += _value;
		} else {
			// ...otherwise, we'll delete the old order and create a new one,
			// accumulating the old order's value:

			// if there is an existing ("old") bid...
			if (oldPrice != 0) {
				// ...then cancel it:
				// first, record the existing value that we're cancelling:
				totalBidValue += receipts[_who].value;
				// if this accounts for the entire price shelf...
				if (prices[oldPrice].totalValue == receipts[_who].value) {
					// ...then wipe it out:
					// if this shelf is the highest...
					if (oldPrice == highestPrice) {
						// ...then replace the highest price with the next lowest:
						highestPrice = prices[oldPrice].nextLowerPrice;
					} else {
						// ...otherwise, unknit the shelf:
						// check we got the right info for the nextHighestOnOldPrice
						if (prices[_nextHighestOnOldPrice].nextLowerPrice != oldPrice) throw;
						// then unknit the shelf:
						prices[_nextHighestOnOldPrice].nextLowerPrice = prices[oldPrice].nextLowerPrice;
					}
					// and delete the shelf:
					delete prices[oldPrice];
				} else {
					// otherwise, just reduce the old bid by the appropriate amount.
					prices[oldPrice].totalValue -= receipts[_who].value;
				}
			}

			// Bail if it's not a sensible unit price.
			if (totalBidValue < _maxUnitPrice) throw;

			if (prices[_maxUnitPrice].totalValue == 0) {
				if (highestPrice == 0) {
					// first bid
					highestPrice = _maxUnitPrice;
				} else {
					// highestPrice becomes the max of itself and the new price:
					if (_maxUnitPrice > highestPrice) {
						// knit in the new price shelf below:
						prices[_maxUnitPrice].nextLowerPrice = highestPrice;
						// record the new highest price "above":
						highestPrice = _maxUnitPrice;
					} else {
						// check we got the right info for the nextHighestPrice
						if (_nextHighestPrice <= _maxUnitPrice || prices[_nextHighestPrice].nextLowerPrice >= _maxUnitPrice) throw;
						// knit in the new price shelf below:
						prices[_maxUnitPrice].nextLowerPrice = prices[_nextHighestPrice].nextLowerPrice;
						// ...and above:
						prices[_nextHighestPrice].nextLowerPrice = _maxUnitPrice;
					}
				}
			}
			// record sender's accumulated bid:
			receipts[_who].value = totalBidValue;
			receipts[_who].price = _maxUnitPrice;
			// add their bid to the new price shelf:
			prices[_maxUnitPrice].totalValue += totalBidValue;
		}
	}

	function deleteHighestShelf() internal {
		if (highestPrice > 0) {
			uint p = prices[highestPrice].nextLowerPrice;
			delete prices[highestPrice];
			highestPrice = p;
		}
	}

	struct Account {
		uint value;
		uint price;
	}

	struct Price {
		uint nextLowerPrice;
		uint totalValue;
	}

	// Constants
	uint public constant TOTAL_MINTABLE = 100;
	uint public constant MINIMUM_STRIKE = 100 finney;
	uint public constant MAXIMUM_STRIKE = 100 ether;
	uint public constant TIE_PHASE_DURATION = 1 minutes;
	uint public begin = now + 0 minutes;
	uint public beginEnd = now + 3 minutes;
	uint public constant END_BLOCK_MAX_DURATION = 1 minutes;
	address public owner = msg.sender;

	// Ongoing auction state
	mapping (address => Account) public receipts;
	mapping (uint => Price) public prices;
	uint public highestPrice = 0;

	// When finding strike price
	bool public ended = false;
	uint public strike = 0;
	uint public totalValue = 0;

	// When found strike price
	uint public tiePhaseBegin = 0;
	uint public totalMinted = 0;

	// Token recorder
	Recorder public tokenRecorder;
}
