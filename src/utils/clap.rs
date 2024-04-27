//! Integration with `clap`

use std::path::PathBuf;

use ruma::OwnedRoomId;

/// Returns the current version of the crate with extra info if supplied
///
/// Set the environment variable `CONDUIT_VERSION_EXTRA` to any UTF-8 string to
/// include it in parenthesis after the SemVer version. A common value are git
/// commit hashes.
#[allow(clippy::doc_markdown)]
fn version() -> String {
	let cargo_pkg_version = env!("CARGO_PKG_VERSION");

	match option_env!("CONDUIT_VERSION_EXTRA") {
		Some(x) => format!("{} ({})", cargo_pkg_version, x),
		None => cargo_pkg_version.to_owned(),
	}
}

/// Commandline arguments
#[derive(clap::Parser, Debug)]
#[clap(version = version(), about, long_about = None)]
pub(crate) struct Args {
	#[arg(short, long)]
	/// Optional argument to the path of a conduwuit config TOML file
	pub(crate) config: Option<PathBuf>,

	#[clap(subcommand)]
	pub(crate) subcmd: Option<Subcmd>,
}

#[derive(clap::Subcommand, Debug)]
pub(crate) enum Subcmd {
	/// Database operations
	YeetRoom {
		room_id: OwnedRoomId,
	},
}

/// Parse commandline arguments into structured data
#[must_use]
pub(crate) fn parse() -> Args { <Args as clap::Parser>::parse() }
