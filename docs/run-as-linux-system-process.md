# Run as a Linux system process

Docker makes it easy to spin up and down environments but it's also possible to run `infer-relay` as a systemd Linux process.
This guide assumes you're on a Linux machine and that Rust is already installed.

## Instructions

### Build infer-relay from source
Start by building the application from source. Here is how to do that:
1. `git clone https://github.com/Inferenco/infer-relay.git`
2. `cd infer-relay`
3. `cargo build --release`

### Place the files where they belong
We want to place the infer-relay binary and the config.toml file where they belong. While still in the root level of the infer-relay folder you cloned in last step, run the following commands:
1. `sudo cp target/release/infer-relay /usr/local/bin/`
2. `sudo mkdir /etc/infer-relay`
3. `sudo cp config.toml /etc/infer-relay/`

### Create the Systemd service file
We need to create a new Systemd service file. These files are placed in the `/etc/systemd/system/` folder where you will find many other services running.

1. `sudo vim /etc/systemd/system/infer-relay.service`
2. Paste in the contents of [this service file](../contrib/infer-relay.service). Remember to replace the `User` value with your own username.
3. Save the file and exit your text editor

### Run the service
To get the service running, we need to reload the systemd daemon and enable the service.

1. `sudo systemctl daemon-reload`
2. `sudo systemctl start infer-relay.service`
3. `sudo systemctl enable infer-relay.service`
4. `sudo systemctl status infer-relay.service`

### Tips

#### Logs
The application will write logs to the journal. To read them, execute `sudo journalctl -f -u infer-relay`
