# Relay JIT Manager

The idea is to resolve relays just in time as the requests from the library user comes in.
This has the benefit, that only the currently needed relays are connected and requests get automatically split. This means that a request is sent only to the relay where its most likely to receive an answer.
This is useful to avoid duplicate data and battery concerns on mobile devices.

## req resolver

![shows how the req relover works](./readme_assets/req_resolver.png "req resolver")

## relay lost connection

![displays what happens when connection is lost and how to recover](./readme_assets/relay_fails.png "relay fails")

## kick unused relays

![introduction of usefulness score](./readme_assets/kick_unused_relays.png "relay fails")
