#[cfg(test)]
mod tests {
    use infer_relay::cli::CLIArgs;

    #[test]
    fn cli_tests() {
        use clap::CommandFactory;
        CLIArgs::command().debug_assert();
    }
}
