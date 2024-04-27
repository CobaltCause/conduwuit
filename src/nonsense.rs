use ruma::RoomId;

use crate::{
	config::Config,
	database::KeyValueDatabase,
	init_tracing_sub, services,
	utils::clap::{Args, Subcmd},
};

pub(crate) fn main(args: Args) -> Result<(), Box<dyn std::error::Error>> {
	let config = Config::new(args.config.as_ref())?;
	let log_handle = init_tracing_sub(&config);

	tokio::runtime::Builder::new_multi_thread()
		.enable_io()
		.enable_time()
		.worker_threads(num_cpus::get())
		.build()
		.expect("should be able to construct tokio runtime")
		.block_on(async move {
			KeyValueDatabase::load_or_create(config, log_handle)
				.await
				.map_err(Into::<Box<dyn std::error::Error>>::into)?;

			match args.subcmd {
				Some(Subcmd::YeetRoom {
					room_id,
				}) => db_room_yeet(room_id).await,
				// This should trigger the server to start
				None => unreachable!(),
			}
		})
}

async fn db_room_yeet<R>(room_id: R) -> Result<(), Box<dyn std::error::Error>>
where
	R: AsRef<RoomId>,
{
	let room_id = room_id.as_ref();

	services().rooms.alias.db.remove_all_aliases(room_id);

	Ok(())
}
