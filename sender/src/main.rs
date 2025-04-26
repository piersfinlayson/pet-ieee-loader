/// ieee-sender.rs
///
/// This example can be used to send data to an IEEE device that support the
/// protocol described [here](https://github.com/piersfinlayson/pet-ieee-loader).
///
/// Specifically, it can be used to send binary data to a Commodore PET via
/// IEEE-488 and trigger the PET to execute it.
/// 
/// It supports three commands:
/// - `--load` - Loads a file into the PET's memory
///     - To load a PRG file, to the location stored in the first two bytes of
///       the file, you just need `--load <FILENAME>`, and supports both BASIC
///       and machine code files.
///     - To load a binary file to a specific address, use `--load --addr
///       <hex_addr> <FILENAME>` - `hex_addr` should be a 4 digit hex address
///       without an 0x or $ prefix.
/// - `--execute` - Execute a machine code routine (using JSR) at a specified address
/// - `--Run` - Runs a BASIC program
/// 
/// Before running this program you must load the loader program into the PET
/// execute it using:
/// 
/// ```basic
/// LOAD "7C00-LOADER",8,1
/// SYS31744
/// ```
use clap::{ArgGroup, Parser};
use std::fmt;
use std::fs::File;
use std::io::Read;
use std::path::Path;
use xum1541::{BusBuilder, DeviceChannel, Error as XumError};

const CMD_EXECUTE: u8 = 0x80;
const CMD_RUN: u8 = 0x81;
const CMD_LOAD: u8 = 0x40;
// Constants for command bytes
#[derive(Debug)]
enum AppError {
    InvalidDevice(String),
    InvalidAddress(String),
    FileNotFound(String),
    FileReadError(String),
    XumError(XumError),
    CommandError(String),
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AppError::InvalidDevice(msg) => write!(f, "Invalid device (0-30): {msg}"),
            AppError::InvalidAddress(msg) => write!(f, "Invalid address: {msg}"),
            AppError::FileNotFound(msg) => write!(f, "File not found: {msg}"),
            AppError::FileReadError(msg) => write!(f, "File read error: {msg}"),
            AppError::XumError(err) => write!(f, "xum1541 error: {err}"),
            AppError::CommandError(msg) => write!(f, "Command error: {msg}"),
        }
    }
}

impl std::error::Error for AppError {}

impl From<XumError> for AppError {
    fn from(err: XumError) -> Self {
        AppError::XumError(err)
    }
}

impl From<std::io::Error> for AppError {
    fn from(err: std::io::Error) -> Self {
        match err.kind() {
            std::io::ErrorKind::NotFound => AppError::FileNotFound(err.to_string()),
            _ => AppError::FileReadError(err.to_string()),
        }
    }
}

// Command line arguments
#[derive(Parser)]
#[command(
    name = "ieee-sender",
    about = "PET IEEE Sender\n\nSends data to a Commodore PET running the IEEE-loader via IEEE-488,\nusing an xum1541 or pico1541.\nCopyright (c) 2025 Piers Finlayson <piers@piers.rocks\nMIT licensed | https://github.com/piersfinlayson/pet-ieee-loader",
    version = "0.1.0"
)]
#[command(group(
    ArgGroup::new("command")
        .required(true)
        .args(["execute", "run", "load"]),
))]
#[allow(clippy::struct_excessive_bools)]
struct CliArgs {
    /// IEEE-488 Device ID to send to
    #[arg(short, long, default_value = "30")]
    device: String,

    /// Send execute command to the PET
    #[arg(short = 'x', long, conflicts_with = "file", requires = "addr")]
    execute: bool,

    /// `RUN` command - runs a BASIC program
    #[arg(short = 'r', long, conflicts_with = "addr", conflicts_with = "file")]
    run: bool,

    /// Send load command to the PET
    #[arg(short, long, requires = "file")]
    load: bool,

    /// The 16-bit hex address (without 0x or $ prefix)
    #[arg(short, long)]
    addr: Option<String>,

    /// File containing data to load (required for load)
    #[arg(requires = "load")]
    file: Option<String>,

    /// Enable verbose output
    #[arg(short, long)]
    verbose: bool,
}

fn main() -> Result<(), AppError> {
    env_logger::init();

    // Parse command line arguments
    let args = CliArgs::parse();

    // Parse device ID
    let device_id = args
        .device
        .parse::<u8>()
        .map_err(|_| AppError::InvalidDevice(args.device.clone()))?;

    // Validate device ID range (0-30 inclusive)
    if device_id > 30 {
        return Err(AppError::InvalidDevice(format!(
            "Device ID must be between 0 and 30, got {device_id}"
        )));
    }

    // Parse address if provided
    let address = if let Some(addr_str) = &args.addr {
        Some(
            u16::from_str_radix(addr_str, 16)
                .map_err(|_| AppError::InvalidAddress(addr_str.clone()))?,
        )
    } else if args.execute {
        return Err(AppError::CommandError(
            "--addr must be specified with --execute".to_string(),
        ));
    } else {
        None
    };

    // Belt and braces - Clap args should have caught this.
    if address.is_some() && args.run {
        return Err(AppError::CommandError(
            "Cannot use --addr with --run command".to_string(),
        ))
    }

    // Get file_name
    let file_path = if args.load {
        Some(args.file.as_ref().ok_or_else(|| {
            AppError::CommandError("File path required for load command".to_string())
        })?)
    } else {
        None
    };

    // Belt and braces - Clap args should have caught this.
    if file_path.is_some() && !args.load {
        return Err(AppError::CommandError(
            "File path can only be used with load command".to_string(),
        ));
    }

    // Connect to the XUM1541 device via USB
    let mut bus = BusBuilder::new().build().map_err(AppError::from)?;

    if args.verbose {
        println!("Initializing bus...");
    }

    // Initialize the bus
    bus.initialize().map_err(AppError::from)?;

    if args.verbose {
        println!("Resetting IEC...");
    }

    // Normally we might reset the IEC bus, but no there's value in doing this
    // when connecting to a PET because the IEEE-488 ~IFC line is not an input.

    if args.verbose {
        println!("Instructing device {device_id} to LISTEN...");
    }

    // Instruct device to LISTEN
    //bus.listen_no_channel(device_id).map_err(AppError::from)?;
    let dc = DeviceChannel::new(device_id, 15)?;
    bus.listen(dc)?;

    // Execute the appropriate command
    if args.execute {
        let address = address.unwrap();

        if args.verbose {
            println!("Sending EXECUTE command at address ${address:04X}...");
        }

        // Handle execute command
        execute_command(&mut bus, address)?;
    } else if args.load {
        let file_path = file_path.unwrap();

        if args.verbose {
            if let Some(addr) = address {
                println!("Sending LOAD command for file {file_path} to address ${addr:04X}...");
            } else {
                println!("Sending LOAD command for file {file_path} using first two bytes as load address");
            }
        }

        load_command(
            &mut bus,
            address,
            file_path,
            args.verbose,
        )?;
    } else if args.run {
        run_command(&mut bus)?;
    }

    if args.verbose {
        println!("Instructing device to stop LISTENing...");
    }

    // Tell the device to stop LISTENing
    bus.unlisten().map_err(AppError::from)?;

    if args.verbose {
        println!("Operation completed successfully");
    }

    Ok(())
}

fn run_command(bus: &mut xum1541::Bus) -> Result<(), AppError> {
    // Send the RUN command
    let command_sequence = [CMD_RUN];
    bus.write(&command_sequence).map_err(AppError::from)?;

    Ok(())
}

fn execute_command(bus: &mut xum1541::Bus, address: u16) -> Result<(), AppError> {
    let addr_low = (address & 0xFF) as u8;
    let addr_high = ((address >> 8) & 0xFF) as u8;

    let command_sequence = [CMD_EXECUTE, addr_low, addr_high];
    bus.write(&command_sequence).map_err(AppError::from)?;

    Ok(())
}

fn load_command(
    bus: &mut xum1541::Bus,
    address: Option<u16>,
    file_path: &str,
    verbose: bool,
) -> Result<(), AppError> {
    // xum1541 supports sending up to 32768 bytes of data.  We require 5 bytes
    // for the command byte, address and length words, so the maximum size is
    // 32768 - 5 = 32763 bytes.
    const MAX_FILE_SIZE: usize = 32763;

    // Check if file exists
    if !Path::new(file_path).exists() {
        return Err(AppError::FileNotFound(file_path.to_string()));
    }

    if verbose {
        println!("Reading file {file_path}...");
    }

    // Read the file
    let mut file = File::open(file_path)?;

    let mut data = Vec::new();
    file.read_to_end(&mut data)?;

    if verbose {
        println!("Read {} bytes from file", data.len());
    }

    // Determine load address and data
    let (load_address, data_to_load, shortened) = if let Some(addr) = address {
        // Use the provided address and the entire file
        (addr, &data[..], false)
    } else {
        // Use the first two bytes from the file as the load address (low byte first)
        let addr = u16::from_le_bytes([data[0], data[1]]);

        if verbose {
            println!("Using address from file: ${addr:04X}");
        }

        (addr, &data[2..], true)
    };

    let addr_low = (load_address & 0xFF) as u8;
    let addr_high = ((load_address >> 8) & 0xFF) as u8;

    let size = data_to_load.len();
    if size > MAX_FILE_SIZE {
        let file_size = if shortened { size + 2 } else { size };
        return Err(AppError::CommandError(format!(
            "File size too large: {file_size} bytes (maximum is 65535)"
        )));
    }

    if verbose {
        println!("Sending load header (address: ${load_address:04X} bytes)...",);
    }

    // Prepare the header
    let header = [CMD_LOAD, addr_low, addr_high];

    // Send the header
    bus.write(&header).map_err(AppError::from)?;

    if verbose {
        println!("Sending data ({size} bytes)...");
    }

    // Send the data
    bus.write(data_to_load).map_err(AppError::from)?;

    if verbose {
        println!("Data sent successfully");
    }

    Ok(())
}
