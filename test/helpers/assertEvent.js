export function assertEvent(results, expectedName, expectedDetails) {
  assert(
    hasEvent(results, expectedName, expectedDetails),
    `Expected to find event ${expectedName} with details ${JSON.stringify(expectedDetails)}`
  );
}

export function assertNoEvent(results, expectedName, expectedDetails) {
  assert(
    !hasEvent(results, expectedName, expectedDetails),
    `Did not expect event ${expectedName} but found it`
  );
}


function hasEvent(results, expectedName, expectedDetails) {
  return results.logs && results.logs.filter(l => isMatch(l, expectedName, expectedDetails)).length > 0;
}

function isMatch(log, expectedName, expectedDetails) {
  if (log.event !== expectedName) return false;

  let keys = expectedDetails ? Object.keys(expectedDetails) : [];
  for (let i=0; i < keys.length; i++) {
    if (log.args[keys[i]] != expectedDetails[keys[i]].toString())
      return false;
  }
  return true;
}