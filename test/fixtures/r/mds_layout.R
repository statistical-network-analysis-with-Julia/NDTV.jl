# Golden fixture for NDTV.jl: MDSLayout against R's classical MDS.
#
#   Rscript test/fixtures/r/mds_layout.R > test/fixtures/mds_layout.toml
#
# MDSLayout is classical (Torgerson) multidimensional scaling of the geodesic
# distances of the symmetrised graph -- stats::cmdscale(sna::geodist(g)$gdist,
# k = 2). A layout is defined up to rotation, reflection, translation and (in
# NDTV.jl, which rescales into [-1, 1]) a uniform scale, so the fixture
# records what is invariant: the pairwise distances between the laid-out
# vertices, divided by their maximum. Random connected graphs on 5-10
# vertices; the odd cases are directed (random orientation; distances are
# taken on the symmetrised graph). Cases whose second and third eigenvalues
# are tied (the 2-D configuration is then not unique) are redrawn.
suppressMessages(library(sna))
seed <- 20261004L
set.seed(seed)
n_cases <- 40L
fmt <- function(x) trimws(formatC(x, digits = 17, format = "g"))

cat('name = "mds_layout"\n\n[provenance]\n')
cat(sprintf('r_version = "%s"\n', paste(R.version$major, R.version$minor, sep = ".")))
cat(sprintf('sna_version = "%s"\n', as.character(packageVersion("sna"))))
cat(sprintf("seed = %d\n", seed))
cat('script = "test/fixtures/r/mds_layout.R"\n')
cat(sprintf('date = "%s"\n', format(Sys.Date())))
cat(sprintf('dataset = "%d random connected graphs on 5-10 vertices (odd cases directed), eigenvalue gap lambda2 - lambda3 > 1e-6"\n', n_cases))
cat("\n[tolerance]\n# Both sides solve the same symmetric eigenproblem in double precision.\ndistance = 1e-8\n\n[values]\n")
cat(sprintf("n_cases = %d\n", n_cases))

g <- 0L
while (g < n_cases) {
  n <- sample(5:10, 1)
  directed <- (g + 1L) %% 2L == 1L
  A <- matrix(0, n, n)
  for (i in 1:(n - 1)) for (j in (i + 1):n) if (runif(1) < 0.3) {
    if (directed && runif(1) < 0.5) A[j, i] <- 1 else A[i, j] <- 1
  }
  S <- pmax(A, t(A))
  D <- geodist(S)$gdist
  if (any(is.infinite(D))) next
  cm <- cmdscale(D, k = 2, eig = TRUE)
  if (cm$eig[2] - cm$eig[3] <= 1e-6 || cm$eig[2] <= 1e-6) next
  g <- g + 1L
  P <- as.matrix(dist(cm$points))
  P <- P / max(P)
  el <- which(A == 1, arr.ind = TRUE)
  cat(sprintf("\n[values.case_%d]\n", g))
  cat(sprintf("n = %d\n", n))
  cat(sprintf("directed = %s\n", if (directed) "true" else "false"))
  cat(sprintf("edges = [%s]\n", paste(sprintf("[%d, %d]", el[, 1], el[, 2]), collapse = ", ")))
  cat(sprintf("distances = [%s]\n", paste(sapply(P[upper.tri(P)], fmt), collapse = ", ")))
}
