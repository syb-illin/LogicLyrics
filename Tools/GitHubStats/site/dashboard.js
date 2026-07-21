"use strict";

const number = new Intl.NumberFormat("en-US");
const shortDate = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric" });
const preciseDate = new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short", timeZone: "UTC" });
let dashboardData = null;
let selectedRange = "30";

const byId = (id) => document.getElementById(id);
const setText = (id, value) => { byId(id).textContent = value; };
const count = (value) => number.format(Number.isFinite(value) ? value : 0);

function appendCell(row, value, scope = false) {
  const cell = document.createElement(scope ? "th" : "td");
  if (scope) cell.scope = "row";
  cell.textContent = value;
  row.append(cell);
  return cell;
}

function renderSummary(data) {
  const repository = data.repository ?? {};
  const traffic = data.traffic ?? {};
  const views = traffic.views ?? {};
  const clones = traffic.clones ?? {};
  setText("appDownloads", count(data.downloads?.app));
  setText("uniqueVisitors", traffic.available ? count(views.uniques) : "Unavailable");
  setText("uniqueCloners", traffic.available ? count(clones.uniques) : "Unavailable");
  setText("stars", count(repository.stars));
  setText("forks", count(repository.forks));
  setText("watchers", count(repository.watchers));
  setText("openIssues", count(repository.openIssues));
  setText("allDownloads", count(data.downloads?.allAssets));
  setText("communityNote", `${count(repository.forks)} forks · ${count(repository.watchers)} watchers`);

  const repositoryLink = byId("repositoryLink");
  if (repository.url) repositoryLink.href = repository.url;
  setText("lastUpdated", `Last snapshot ${preciseDate.format(new Date(data.capturedAt))} UTC`);

  const status = byId("trafficStatus");
  const permissionNotice = byId("permissionNotice");
  if (traffic.available) {
    status.textContent = traffic.complete ? "GitHub Traffic connected" : "GitHub Traffic partially available";
    status.classList.add("connected");
    permissionNotice.hidden = true;
  } else {
    status.textContent = traffic.reason === "permission-required" ? "Traffic permission needed" : "Traffic temporarily unavailable";
    permissionNotice.hidden = false;
  }
}

function renderReleases(releases = []) {
  const body = byId("releaseRows");
  body.replaceChildren();
  if (!releases.length) {
    const row = body.insertRow();
    const cell = row.insertCell();
    cell.colSpan = 3;
    cell.textContent = "No GitHub releases found.";
    return;
  }
  releases.forEach((release) => {
    const row = document.createElement("tr");
    const versionCell = document.createElement("th");
    versionCell.scope = "row";
    const link = document.createElement("a");
    link.href = release.url;
    link.textContent = release.tag || release.name || "Release";
    versionCell.append(link);
    row.append(versionCell);
    appendCell(row, release.publishedAt ? shortDate.format(new Date(release.publishedAt)) : "—");
    appendCell(row, count(release.appDownloads));
    body.append(row);
  });
}

function renderSimpleTable(bodyId, items, firstKey, firstFallback) {
  const body = byId(bodyId);
  body.replaceChildren();
  if (!items.length) {
    const row = body.insertRow();
    const cell = row.insertCell();
    cell.colSpan = 3;
    cell.textContent = firstFallback;
    return;
  }
  items.forEach((item) => {
    const row = document.createElement("tr");
    appendCell(row, String(item[firstKey] || "—"), true);
    appendCell(row, count(item.count));
    appendCell(row, count(item.uniques));
    body.append(row);
  });
}

function trafficPoints(data) {
  return Object.entries(data.history?.dailyTraffic ?? {}).map(([date, values]) => ({
    date,
    views: Number(values.views || 0),
    uniqueVisitors: Number(values.uniqueVisitors || 0),
    clones: Number(values.clones || 0),
    uniqueCloners: Number(values.uniqueCloners || 0),
  })).sort((left, right) => left.date.localeCompare(right.date));
}

function selectedPoints(points) {
  if (selectedRange === "all") return points;
  return points.slice(-Number(selectedRange));
}

function svgElement(name, attributes = {}) {
  const element = document.createElementNS("http://www.w3.org/2000/svg", name);
  Object.entries(attributes).forEach(([key, value]) => element.setAttribute(key, String(value)));
  return element;
}

function renderChart(data) {
  const allPoints = trafficPoints(data);
  const points = selectedPoints(allPoints);
  const chart = byId("trafficChart");
  const chartContainer = byId("chartContainer");
  const empty = byId("chartEmpty");
  const title = svgElement("title", { id: "chartTitle" });
  title.textContent = "Daily repository views and clones";
  const description = svgElement("desc", { id: "chartDescription" });
  description.textContent = `GitHub traffic for ${points.length} archived days.`;
  chart.replaceChildren(title, description);

  if (!points.length) {
    chartContainer.hidden = true;
    empty.hidden = false;
    renderTrafficTable(allPoints);
    return;
  }
  chartContainer.hidden = false;
  empty.hidden = true;

  const width = 960;
  const height = 320;
  const inset = { top: 20, right: 18, bottom: 42, left: 50 };
  const plotWidth = width - inset.left - inset.right;
  const plotHeight = height - inset.top - inset.bottom;
  const maximum = Math.max(1, ...points.flatMap((point) => [point.views, point.clones]));
  const x = (index) => inset.left + (points.length === 1 ? plotWidth / 2 : (index / (points.length - 1)) * plotWidth);
  const y = (value) => inset.top + plotHeight - (value / maximum) * plotHeight;

  for (let step = 0; step <= 4; step += 1) {
    const lineY = inset.top + (step / 4) * plotHeight;
    chart.append(svgElement("line", { x1: inset.left, y1: lineY, x2: width - inset.right, y2: lineY, class: "grid-line" }));
    const label = svgElement("text", { x: inset.left - 10, y: lineY + 4, "text-anchor": "end", class: "axis-label" });
    label.textContent = count(Math.round(maximum * (1 - step / 4)));
    chart.append(label);
  }

  const labelIndexes = [...new Set([0, Math.floor((points.length - 1) / 2), points.length - 1])];
  labelIndexes.forEach((index) => {
    const label = svgElement("text", { x: x(index), y: height - 10, "text-anchor": index === 0 ? "start" : index === points.length - 1 ? "end" : "middle", class: "axis-label" });
    label.textContent = shortDate.format(new Date(`${points[index].date}T00:00:00Z`));
    chart.append(label);
  });

  [["views", "traffic-line views"], ["clones", "traffic-line clones"]].forEach(([key, className]) => {
    const coordinates = points.map((point, index) => `${x(index)},${y(point[key])}`).join(" ");
    chart.append(svgElement("polyline", { points: coordinates, class: className }));
  });
  renderTrafficTable(allPoints);
}

function renderTrafficTable(points) {
  const body = byId("trafficDataRows");
  body.replaceChildren();
  [...points].reverse().forEach((point) => {
    const row = document.createElement("tr");
    appendCell(row, shortDate.format(new Date(`${point.date}T00:00:00Z`)), true);
    appendCell(row, count(point.views));
    appendCell(row, count(point.uniqueVisitors));
    appendCell(row, count(point.clones));
    appendCell(row, count(point.uniqueCloners));
    body.append(row);
  });
}

function configureRangeButtons() {
  document.querySelectorAll("[data-range]").forEach((button) => {
    button.addEventListener("click", () => {
      selectedRange = button.dataset.range;
      document.querySelectorAll("[data-range]").forEach((candidate) => candidate.setAttribute("aria-pressed", String(candidate === button)));
      if (dashboardData) renderChart(dashboardData);
    });
  });
}

async function loadDashboard() {
  configureRangeButtons();
  try {
    const response = await fetch("data/dashboard.json", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    dashboardData = await response.json();
    renderSummary(dashboardData);
    renderReleases(dashboardData.releases);
    renderSimpleTable("referrerRows", dashboardData.traffic?.referrers ?? [], "referrer", "No referrer data available.");
    renderSimpleTable("pathRows", dashboardData.traffic?.popularPaths ?? [], "title", "No popular-content data available.");
    renderChart(dashboardData);
  } catch (error) {
    const status = byId("trafficStatus");
    status.textContent = "Dashboard unavailable";
    setText("lastUpdated", "The generated GitHub data could not be loaded. Try again after the next workflow run.");
    console.error("Unable to load GitHub dashboard", error);
  }
}

loadDashboard();
