use clap::Parser;

mod args;
mod atlas_ops;

fn main() {
    let _cli = args::Cli::parse();
}
