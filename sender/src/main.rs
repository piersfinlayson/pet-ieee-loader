/// ieee-sender.rs
///
/// This example can be used to send data to an IEEE device that support the
/// protocol described [here](https://github.com/piersfinlayson/pet-ieee-loader).
///
/// Specifically, it can be used to send binary data to a Commodore PET via
/// IEEE-488 and trigger the PET to execute it.
use clap::{ArgGroup, Parser};
use std::fmt;
use std::fs::File;
use std::io::Read;
use std::path::Path;
use xum1541::{BusBuilder, Error as XumError};

const CMD_EXECUTE: u8 = 0x80;
const CMD_LOAD: u8 = 0x40;

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
        .args(["execute", "load"]),
))]
#[allow(clippy::struct_excessive_bools)]
struct CliArgs {
    /// IEEE-488 Device ID to send to
    #[arg(short, long, default_value = "30")]
    device: String,

    /// Send execute command to the PET
    #[arg(short = 'x', long)]
    execute: bool,

    /// Send load command to the PET
    #[arg(short, long)]
    load: bool,

    /// The 16-bit hex address (without 0x or $ prefix)
    #[arg(short, long, required_unless_present = "use_file_addr")]
    addr: Option<String>,

    /// File containing data to load (required for load)
    #[arg(requires = "load")]
    file: Option<String>,

    /// Use the first two bytes of the file as the load address
    #[arg(long, requires = "load", conflicts_with = "addr")]
    use_file_addr: bool,

    /// Enable verbose output
    #[arg(short, long)]
    verbose: bool,
}

fn main() -> Result<(), AppError> {
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
    } else if args.use_file_addr {
        // Address will be parsed from file later
        None
    } else {
        return Err(AppError::CommandError(
            "Either --addr or --use-file-addr must be specified".to_string(),
        ));
    };

    // Get file_name
    let file_path = if args.load {
        Some(args.file.as_ref().ok_or_else(|| {
            AppError::CommandError("File path required for load command".to_string())
        })?)
    } else {
        None
    };

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
    bus.listen_no_channel(device_id).map_err(AppError::from)?;

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
                println!("Sending LOAD command for file {file_path}...");
            }
            if args.use_file_addr {
                println!("Using first two bytes of file as load address");
            }
        }

        load_command(
            &mut bus,
            address,
            file_path,
            args.use_file_addr,
            args.verbose,
        )?;
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
    use_file_addr: bool,
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
    let (load_address, data_to_load, shortened) = if use_file_addr && data.len() >= 2 {
        // Use the first two bytes from the file as the load address (low byte first)
        let addr = u16::from_le_bytes([data[0], data[1]]);
        
        if verbose {
            println!("Using address from file: ${addr:04X}");
        }
        
        (addr, &data[2..], true)
    } else {
        // Use the provided address and the entire file
        let addr = address.ok_or_else(|| 
            AppError::CommandError("Address required for load command when not using file address".to_string()))?;
        (addr, &data[..], false)
    };

    let addr_low = (load_address & 0xFF) as u8;
    let addr_high = ((load_address >> 8) & 0xFF) as u8;

    let size = data_to_load.len();
    if size > MAX_FILE_SIZE {
        let file_size = if shortened {
            size + 2
        } else {
            size
        };
        return Err(AppError::CommandError(format!(
            "File size too large: {file_size} bytes (maximum is 65535)"
        )));
    }

    #[allow(clippy::cast_possible_truncation)]
    let (size_low, size_high) = ((size & 0xFF) as u8, ((size >> 8) & 0xFF) as u8);

    if verbose {
        println!(
            "Sending load header (address: ${load_address:04X}, size: {size}/${size:04X} bytes)...",
        );
    }

    // Prepare the header
    let header = [CMD_LOAD, addr_low, addr_high, size_low, size_high];

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
