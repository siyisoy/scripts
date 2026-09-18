# 🛠️ Scripts

A personal collection of **Bash scripts and command-line utilities** created to automate repetitive tasks, simplify Linux administration, and document useful solutions encountered in day-to-day work.

The repository serves both as a toolbox and as a reference for scripts that may be useful across different Linux systems.

## 📦 What's Here?

The scripts in this repository cover a variety of purposes, including:

* Linux system administration and maintenance
* Desktop and display configuration
* File and directory management
* Networking and connectivity
* Software installation and configuration
* Automation of repetitive command-line tasks
* Development and research workflow utilities
* Small fixes and workarounds worth keeping for future use

The collection will evolve as new scripts are added or existing ones are improved.

## 🚀 Usage

Clone the repository:

```bash
git clone git@github.com:siyisoy/scripts.git
cd scripts
```

Before running a script, inspect its contents:

```bash
less script.sh
```

Make it executable if necessary:

```bash
chmod +x script.sh
```

Then run it:

```bash
./script.sh
```

Some scripts may require administrator privileges:

```bash
sudo ./script.sh
```

Only use `sudo` when the script actually requires elevated privileges and you understand what the script does.

## ⚠️ Use at Your Own Risk

These scripts were primarily written for my own systems and workflows.

They may make assumptions about the operating system, installed packages, directory structure, hardware, environment variables, or system configuration. A script that works correctly on one machine may behave differently on another.

**Always read and understand a script before executing it, especially when running it with root privileges.**

No guarantee is provided that the scripts will work correctly on every system. Use them at your own risk.

## 🔧 Compatibility

Unless otherwise stated, the scripts are intended primarily for Linux systems using common GNU/Linux command-line utilities.

Individual scripts may have additional dependencies or distribution-specific requirements. Where relevant, these should be documented within the script or accompanying documentation.

## 📁 Repository Philosophy

The goal is to keep these scripts:

* understandable,
* reasonably portable,
* easy to modify,
* useful from the command line,
* and documented well enough to be reused later.

Rather than treating every small utility as a separate project, this repository provides a common home for practical scripts worth keeping under version control.

## 📜 License

Unless a specific script states otherwise, please check the repository's license before redistributing or incorporating these scripts into other projects.

Contributions, improvements, and suggestions are welcome.

