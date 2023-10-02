<p align="center">
  <a href="" rel="noopener">
 <img width=200px height=200px src="./asset/ufmg_rnai.png" alt="Project logo"></a>
</p>

<h3 align="center">small RNA Metavir</h3>

<div align="center">

[![Status](https://img.shields.io/badge/status-active-success.svg)]()
<!-- [![GitHub Issues](https://img.shields.io/github/issues/kylelobo/The-Documentation-Compendium.svg)](https://github.com/kylelobo/The-Documentation-Compendium/issues) -->
<!-- [![GitHub Pull Requests](https://img.shields.io/github/issues-pr/kylelobo/The-Documentation-Compendium.svg)](https://github.com/kylelobo/The-Documentation-Compendium/pulls) -->
<!-- [![License](https://img.shields.io/badge/license-MIT-blue.svg)](/LICENSE) -->

</div>

---

<p align="center">
  An automated independent of sequence similarity tool for viral sequences identification using RNA-seq metagenomics small RNA reads.
</p>

## Table of Contents

- [About](#about)
- [Getting Started](#getting_started)
<!-- - [Deployment](#deployment) -->
<!-- - [Usage](#usage) -->
<!-- - [Built Using](#built_using) -->
<!-- - [Contributing](../CONTRIBUTING.md) -->
<!-- - [Authors](#authors) -->
<!-- - [Acknowledgments](#acknowledgement) -->

## About <a name="about"></a>

This is an automated tool designed to support the identification of viral sequences in an independent of sequence similarity way. By exploring the unique signatures of small RNA size profiles, the tool can detect viral contigs among sequences that were previously not identified by sequence similarity search tools like BLAST or Diamond.

_Small RNA Metavir_ includes a data engineering pipeline to assemble and classify contigs using small RNA sequencing reads. Initially, assembled contigs are classified as `viral`, `non-viral`, or `unknown` using sequence similarity methods. Following that, small RNA size profiles are generated for each contig, resulting in structured representations that can be further analyzed by traditional machine learning algorithms. A Random Forest classifier, trained with small RNA size profile representations of over 1300 curated sequences, is used to refine the classification. The output is made of all assembled contigs represented by numerical features, classified as either `non-viral`, `unknown`, `viral`, or `EVEs`.


## Getting Started <a name="getting_started"></a>

<!-- These instructions will get you a copy of the project up and running on your local machine for development and testing purposes. See [deployment](#deployment) for notes on how to deploy the project on a live system. -->

### Dependencies

__Host and bacteria genome references__

To filter host genome and bacteria reads the user needs to have these respective reference sequence `.fasta` files.

__Nucleotide and amino acid databases__

To run the sequence similarity based classification stages the user must provide the corresponding `nt` and `nr` databse files.


<!-- 
```
Give examples
```

### Installing

A step by step series of examples that tell you how to get a development env running.

Say what the step will be

```
Give the example
```

And repeat

```
until finished
```

End with an example of getting some data out of the system or using it for a little demo. -->

<!-- ## 🔧 Running the tests <a name = "tests"></a>

Explain how to run the automated tests for this system.

### Break down into end to end tests

Explain what these tests test and why

```
Give an example
```

### And coding style tests

Explain what these tests test and why

```
Give an example
``` -->
<!-- 
## Usage <a name="usage"></a>

Add notes about how to use the system. -->

<!-- ## 🚀 Deployment <a name = "deployment"></a>

Add additional notes about how to deploy this on a live system. -->
<!-- 
## ⛏️ Built Using <a name = "built_using"></a>

- [MongoDB](https://www.mongodb.com/) - Database
- [Express](https://expressjs.com/) - Server Framework
- [VueJs](https://vuejs.org/) - Web Framework
- [NodeJs](https://nodejs.org/en/) - Server Environment -->

<!-- ## ✍️ Authors <a name = "authors"></a>

- [@kylelobo](https://github.com/kylelobo) - Idea & Initial work

See also the list of [contributors](https://github.com/kylelobo/The-Documentation-Compendium/contributors) who participated in this project.

## 🎉 Acknowledgements <a name = "acknowledgement"></a>

- Hat tip to anyone whose code was used
- Inspiration
- References -->
