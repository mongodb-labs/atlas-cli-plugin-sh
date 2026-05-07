use clap::Parser;

mod args;
mod atlas_ops;
mod credentials;

fn main() {
    let _cli = args::Cli::parse();
}
