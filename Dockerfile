# Dockerfile for OneCodeToFindThemAll + Aggregation
# Builds a container with Perl and Julia environments for:
#   - build_dictionary.pl: Build LTR index/dictionary from RepeatMasker output
#   - one_code_to_find_them_all.pl: Curate TE calls from RepeatMasker output
#   - aggregate.jl: Aggregate and format output files

FROM julia:1.10

# 1. Install Perl and system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        perl \
        libfile-find-rule-perl \
        libgetopt-long-descriptive-perl \
    && rm -rf /var/lib/apt/lists/*

# 2. Configure Global Julia Environment for Apptainer/HPC usage
ENV JULIA_DEPOT_PATH=/opt/julia
ENV JULIA_PKGDIR=/opt/julia

# 3. Install Julia Packages required by aggregate.jl
RUN julia -e 'using Pkg; Pkg.add(["DataFrames", "CSV", "ArgParse", "Pipe", "Logging"]); Pkg.precompile()'

# 4. Fix Permissions for HPC/Apptainer compatibility
RUN chmod -R 777 /opt/julia

# 5. Create scripts directory
RUN mkdir -p /opt/onecodetofindthemall

# 6. Copy Perl scripts for OneCodeToFindThemAll
COPY build_dictionary.pl /opt/onecodetofindthemall/
COPY one_code_to_find_them_all.pl /opt/onecodetofindthemall/

# 7. Copy Julia aggregation script
COPY aggregate.jl /opt/onecodetofindthemall/

# 8. Make all scripts executable and add to PATH
RUN chmod +x /opt/onecodetofindthemall/*.pl && \
    chmod +x /opt/onecodetofindthemall/*.jl

ENV PATH="/opt/onecodetofindthemall:${PATH}"

# 9. Create version file for tracking
RUN echo "onecodetofindthemall: 1.0.0" > /opt/onecodetofindthemall/VERSION

# Default command
CMD ["bash"]