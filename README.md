# Learnshell

Learnshell helps you test scripts in a semi-isolated semi-consistent way.
It is a framework to test user bash scripts, and to present assignments to users
in a pleasant way, while learning to work in a terminal

## Usage

```sh
# Lists known assignments
./learnshell.sh

# Prints the assignment information
./learnshell.sh ID

# Runs tests on script
./learnshell.sh ID script.sh

# Example usage
./learnshell.sh hello examples/hello.sh
```

## Organisations

Learnshell takes assignments and tests from the default assignment and test
folders, but it can also take them from assignments.\* and tests.\* directories,
where \* is replaced with the name of an organisation.
