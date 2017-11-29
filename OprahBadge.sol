//! The Oprah-Badge contract.
//!
//! You get a badge! And you get a badge! You get a badge, too!
//!
//! Copyright 2016 Jannis Redmann, Parity Technologies Ltd.
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

pragma solidity ^0.4.6;

import "Owned.sol";
import "Certifier.sol";

contract OprahBadge is Owned, Certifier {
    struct Certification {
        bool active;
        mapping (string => bytes32) meta;
    }

    function certify() {
        if (certs[msg.sender].active) return;
        certs[msg.sender].active = true;
        Confirmed(msg.sender);
    }
    function revoke() {
        if (!certs[msg.sender].active) throw;
        certs[msg.sender].active = false;
        Revoked(msg.sender);
    }
    function certified(address _who) constant returns (bool) { return certs[_who].active; }
    function get(address _who, string _field) constant returns (bytes32) { return certs[_who].meta[_field]; }
    function getAddress(address _who, string _field) constant returns (address) { return address(certs[_who].meta[_field]); }
    function getUint(address _who, string _field) constant returns (uint) { return uint(certs[_who].meta[_field]); }

    mapping (address => Certification) certs;
}
