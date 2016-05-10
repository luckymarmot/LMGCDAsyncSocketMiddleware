# LMGCDAsyncSocketMiddleware

A middleware for CocoaAsyncSocket's TCP GCDAsyncSocket.

> Note: while this code has been in production in [Paw](https://luckymarmot.com/paw) for a while, it still needs structural improvements to be a nice library. Also, some unit tests would be very useful. Contributions are more than welcome! :)

## Improvements over GCDAsyncSocket

- Implements the [Happy Eyeballs Algorithm](https://en.wikipedia.org/wiki/Happy_Eyeballs) to connect to the fastest host (IPv4 or IPv6) when both are returned by the DNS server
- Wraps nicely all read operations (read until a data has been found, read a given number of bytes, read until connection close)
- Wraps GCDAsyncSocket, so the caller can abstract itself from other details
- Adds a new delegate callback `didResolveHostnameWithIPv4Address:` as soon as DNS resolution happens

## License

Copyright 2016 [Paw](https://luckymarmot.com/paw). MIT License. See LICENSE.md.
