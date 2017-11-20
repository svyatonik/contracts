//! Oprah Badge contract
//! You get a badge! And you get a badge! You get a badge too!
//! By Jannis R, 2016.

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
