// Cloudflare's outbound TCP socket API, kept in its own file so mailer.js can be
// tested in Node with a fake socket.
export { connect } from 'cloudflare:sockets';
