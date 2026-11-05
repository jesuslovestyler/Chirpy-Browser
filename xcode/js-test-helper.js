// Chirpy Browser 0.33 drill helper — the external
// script for js-test.html. The test page loads this
// file through the fetcher (the Shield first, then
// the cache), and its gifts — one function, one
// number — land on the page's shared scope, where
// the page's own inline script picks them up
// (promise 9 on the test page).

function chirpyHelperGreet(name) {
  return "Hello, " + name + " — this sentence was fetched from a separate file.";
}

var chirpyHelperNumber = 6 * 7;
