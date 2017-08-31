//! Token Registry contract.
//! By ParityTech, 2017.
//! Released under the Apache Licence 2.
/**
 * Usage:
    const tokensBytecode = '0x...';

    const tokensBalancesBytecode = '0x...';

    const who = [
    '0x0000000000000000000000000000000000000000'
    ];

    const tokenRegAddress = '0x5F0281910Af44bFb5fC7e86A404d0304B0e042F1';
    const tokenFrom = 25;
    const tokenCount = 50;

    const tokensCalldata = tokensBytecode + [
      tokenRegAddress.replace('0x', ''),
      tokenFrom.toString(16),
      tokenCount.toString(16)
    ].map((v) => v.padStart(64, 0)).join('');

    let tokens;

    api.eth
    .call({
      data: tokensCalldata
    })
    .then((result) => {
      const results = result
        .replace('0x', '')
        .match(/.{1,64}/g)
        .map((str) => '0x' + str);

      tokens = results
        .slice(1)
        .filter((address) => !/^(0x)?0*$/.test(address))
        .map((address) => '0x' + address.slice(-40));
    })
    .then(() => {
      let tokensBalancesCallData = tokensBalancesBytecode;

      tokensBalancesCallData += [].concat(
        (32 * 2).toString(16),
        (32 * 3 + 32 * who.length).toString(16),

        who.length.toString(16),
        who.map((address) => address.replace('0x', '')),

        tokens.length.toString(16),
        tokens.map((address) => address.replace('0x', ''))
      ).map((v) => v.padStart(64, 0)).join('');

      console.log(tokens)

      return api.eth.call({ data: tokensBalancesCallData });
    })
    .then((result) => {
      const results = result
        .replace('0x', '')
        .match(/.{1,64}/g)
        .map((str) => '0x' + str);

      const balances = {};

      who.forEach((address, whoIndex) => {
        balances[address] = {};

        tokens.forEach((token, tokenIndex) => {
          const index = 1 + whoIndex * tokens.length + tokenIndex;
          const balance = parseInt(results[index], 16);

          balances[address][token] = balance;
        });
      });

      return balances;
    });
 */

pragma solidity ^0.4.10;

contract TokenReg {
  function tokenCount() constant returns (uint);
  function token(uint _id) constant returns (address addr, string tla, uint base, string name, address owner);
}

contract Tokens {
  function Tokens (address tokenRegAddress, uint start, uint max)
  {
    TokenReg tokenReg = TokenReg(tokenRegAddress);

    uint tokensCount = tokenReg.tokenCount();
    uint count;

    if (start + max > tokensCount) {
      count = tokensCount - start;
    } else {
      count = max;
    }

    // The size is 32 bytes for each
    // value, plus 32 bytes for the count
    uint m_size = 32 * count + 32;

    address[] memory tokens;

    assembly {
      tokens := mload(0x40)
      mstore(0x40, add(tokens, m_size))
      mstore(tokens, count)
    }

    for (uint i = start; i < start + count; i++) {
      (tokens[i - start],) = tokenReg.token(i);
    }

    assembly {
      return (tokens, m_size)
    }
  }
}

contract TokensBalances {
  function TokensBalances (address[] memory who, address[] memory tokens)
  {
    uint count = tokens.length * who.length;

    // The size is 32 bytes for each
    // value, plus 32 bytes for the count
    uint m_size = 32 * count + 32;
    bytes4 signature = 0x70a08231;
    uint[] memory balances;
    uint m_in;

    assembly {
      balances := mload(0x40)
      mstore(0x40, add(balances, m_size))
      mstore(balances, count)

      m_in := mload(0x40)
      mstore(0x40, add(m_in, 0x24))
      mstore(m_in, signature)
    }

    for (uint i = 0; i < who.length; i++) {
      for (uint j = 0; j < tokens.length; j++) {
        address w = who[i];
        address t = tokens[j];
        uint offset = 32 * (1 + i * tokens.length + j);

        assembly {
          let m_out := add(balances, offset)
          mstore(add(m_in, 0x4), w)
          call(0xffff, t, 0x0, m_in, 0x24, m_out, 0x20)
          pop
        }
      }
    }

    assembly {
      return (balances, m_size)
    }
  }
}
