/// Where the API lives.
///
/// The deployment sits behind Cloudflare, which answers 403 (error 1010) to a
/// request carrying no User-Agent at all. Dio sends Dart's own string, so this
/// works as it stands — but anything here that clears the header will be
/// refused before it reaches the API.
const String apiBaseUrl = 'https://toannd.work/api/v1';
// const String apiBaseUrl = 'http://localhost:8000/api/v1';


/// The dev machine on the local network, for when the backend is being run
/// from source. `ipconfig` gives this address and it changes with DHCP.
const String localApiBaseUrl = 'http://192.168.100.84:8000/api/v1';
